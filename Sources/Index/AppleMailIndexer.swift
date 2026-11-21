import Foundation

/// Indexes Apple Mail (.emlx) with NO message-count cap and proper header decoding.
final class AppleMailIndexer: @unchecked Sendable {
    static let shared = AppleMailIndexer()

    private let store = IndexStore.shared
    private let queue = DispatchQueue(label: "dadsearch.applemail", qos: .utility)
    private var debounce: DispatchWorkItem?

    static var mailRoots: [URL] {
        let lib = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mail")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: lib.path)) ?? []
        // Works for V10, V11 … whatever macOS ships next.
        return names.filter { $0.hasPrefix("V") && Int($0.dropFirst()) != nil }.map { lib.appendingPathComponent($0) }
    }

    func scheduleSync(after delay: TimeInterval = 30) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.debounce?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.sync() }
            self.debounce = item
            self.queue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    func sync() {
        let known = store.signatures(sources: ["applemail"])
        var keep = Set<String>()
        var batch: [IndexRecord] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]

        for root in AppleMailIndexer.mailRoots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                guard url.pathExtension.lowercased() == "emlx" else { continue }
                let key = "mail:" + url.path
                keep.insert(key)
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let mtime = v.contentModificationDate ?? Date()
                let size = Int64(v.fileSize ?? 0)
                if let sig = known[key], sig.0 == mtime.timeIntervalSince1970, sig.1 == size { continue }
                guard let parsed = AppleMailIndexer.parse(url) else { continue }
                batch.append(IndexRecord(
                    key: key, path: url.path,
                    name: parsed.subject.isEmpty ? "(no subject)" : parsed.subject,
                    kind: .email, source: "applemail", ext: "emlx", size: size,
                    mtime: parsed.date ?? mtime, added: parsed.date ?? mtime,
                    sender: parsed.from, origin: "Apple Mail " + parsed.to,
                    hidden: false, snippet: String(parsed.body.prefix(300)), ref: "",
                    body: parsed.body, needsExtraction: false
                ))
                if batch.count >= 500 { store.upsert(batch); batch.removeAll(keepingCapacity: true) }
            }
        }
        if !batch.isEmpty { store.upsert(batch) }
        if !keep.isEmpty { store.deleteMissing(source: "applemail", keep: keep) }
    }

    // MARK: - .emlx parsing

    struct ParsedMail { var subject = ""; var from = ""; var to = ""; var date: Date?; var body = "" }

    static func parse(_ url: URL) -> ParsedMail? {
        guard let handle = try? FileHandle(forReadingFrom: url), let data = try? handle.read(upToCount: 600_000) else { return nil }
        try? handle.close()
        // First line is the byte length of the RFC-822 message that follows.
        guard let nl = data.firstIndex(of: 0x0A) else { return nil }
        let message = data[data.index(after: nl)...]
        let text = String(decoding: message, as: UTF8.self)   // lossy: never drops a message because of one odd byte

        var headerPart = text
        var bodyPart = ""
        if let r = text.range(of: "\r\n\r\n") ?? text.range(of: "\n\n") {
            headerPart = String(text[..<r.lowerBound])
            bodyPart = String(text[r.upperBound...])
        }
        // Unfold continuation lines
        let unfolded = headerPart.replacingOccurrences(of: "\r?\n[ \t]+", with: " ", options: .regularExpression)
        func header(_ name: String) -> String {
            for line in unfolded.components(separatedBy: .newlines) where line.lowercased().hasPrefix(name.lowercased() + ":") {
                return RFC2047.decode(String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces))
            }
            return ""
        }
        var mail = ParsedMail()
        mail.subject = header("Subject")
        mail.from = header("From")
        mail.to = header("To")
        let dateString = header("Date")
        if !dateString.isEmpty {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss z"] {
                f.dateFormat = fmt
                if let d = f.date(from: dateString) { mail.date = d; break }
            }
        }
        var body = bodyPart
        if unfolded.lowercased().contains("quoted-printable") {
            body = body.replacingOccurrences(of: "=\r?\n", with: "", options: .regularExpression)
        }
        body = body.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let lines = body.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("--") || t.hasPrefix("Content-") { return false }
            return !(t.count > 60 && !t.contains(" "))       // drops base64 attachment blocks
        }
        mail.body = String(lines.joined(separator: " ").prefix(20_000))
        return mail
    }
}

/// Decodes "=?UTF-8?B?...?=" / "=?ISO-8859-1?Q?...?=" header words.
enum RFC2047 {
    static func decode(_ input: String) -> String {
        guard input.contains("=?"), let regex = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=") else { return input }
        let ns = input as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if !between.trimmingCharacters(in: .whitespaces).isEmpty { result += between }
            let charset = ns.substring(with: m.range(at: 1))
            let enc = ns.substring(with: m.range(at: 2)).lowercased()
            let payload = ns.substring(with: m.range(at: 3))
            var bytes = Data()
            if enc == "b" {
                bytes = Data(base64Encoded: payload) ?? Data()
            } else {
                let q = payload.replacingOccurrences(of: "_", with: " ")
                var i = q.startIndex
                while i < q.endIndex {
                    if q[i] == "=", q.distance(from: i, to: q.endIndex) >= 3,
                       let byte = UInt8(q[q.index(i, offsetBy: 1)...q.index(i, offsetBy: 2)], radix: 16) {
                        bytes.append(byte)
                        i = q.index(i, offsetBy: 3)
                    } else {
                        bytes.append(contentsOf: Array(String(q[i]).utf8))
                        i = q.index(after: i)
                    }
                }
            }
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            let nsEnc = cfEnc == kCFStringEncodingInvalidId ? String.Encoding.utf8.rawValue : CFStringConvertEncodingToNSStringEncoding(cfEnc)
            result += String(data: bytes, encoding: String.Encoding(rawValue: nsEnc)) ?? String(decoding: bytes, as: UTF8.self)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
