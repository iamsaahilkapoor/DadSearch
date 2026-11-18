import Foundation
import zlib

public final class OutlookSearchEngine: @unchecked Sendable {
    public static let shared = OutlookSearchEngine()

    private let fileManager = FileManager.default
    private var cachedEmailIndex: [SearchItem] = []
    private var lastIndexTime: Date = .distantPast

    public init() {}

    private var outlookProfileDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            home.appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles"),
            home.appendingPathComponent("Library/Containers/com.microsoft.Outlook/Data/Library/Caches"),
            home.appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/Outlook")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private var appleMailDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            home.appendingPathComponent("Library/Mail/V10"),
            home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail/V10")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func searchOutlookMessages(keyword: String, limit: Int = 40) -> [SearchItem] {
        // Refresh local cache every 3 minutes
        if cachedEmailIndex.isEmpty || Date().timeIntervalSince(lastIndexTime) > 180 {
            rebuildEmailIndex()
        }

        if keyword.isEmpty {
            return Array(cachedEmailIndex.prefix(limit))
        }

        let lower = keyword.lowercased()
        let matches = cachedEmailIndex.filter { item in
            item.title.localizedCaseInsensitiveContains(lower) ||
            item.subtitle.localizedCaseInsensitiveContains(lower) ||
            (item.matchSnippet?.localizedCaseInsensitiveContains(lower) == true)
        }

        return Array(matches.prefix(limit))
    }

    private func rebuildEmailIndex() {
        var items: [SearchItem] = []

        // 1. Index New Outlook EFMData (.dat gzipped files) & Attachments
        for dir in outlookProfileDirectories {
            let filesDir = dir.appendingPathComponent("Main Identity/Files")
            if fileManager.fileExists(atPath: filesDir.path) {
                indexNewOutlookFiles(at: filesDir, into: &items)
            }
        }

        // 2. Index Apple Mail (.emlx)
        for mailDir in appleMailDirectories {
            indexAppleMail(at: mailDir, into: &items)
        }

        // 3. Fallback: Index Legacy Outlook (.olk15Message)
        for dir in outlookProfileDirectories {
            indexLegacyOutlook(at: dir, into: &items)
        }

        // Sort by modification date descending
        items.sort { $0.modificationDate > $1.modificationDate }

        self.cachedEmailIndex = items
        self.lastIndexTime = Date()
    }

    // MARK: - New Outlook (.dat EFMData & Attachments)
    private func indexNewOutlookFiles(at rootURL: URL, into items: inout [SearchItem]) {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let path = fileURL.path
            let modDate = values.contentModificationDate ?? Date()
            let size = Int64(values.fileSize ?? 0)

            // Handle New Outlook Email Body (.dat in EFMData)
            if path.contains("EFMData") && fileURL.pathExtension.lowercased() == "dat" {
                if let data = try? Data(contentsOf: fileURL),
                   let decompressed = decompressGzip(data: data),
                   let html = String(data: decompressed, encoding: .utf8) {

                    let (title, snippet) = extractCleanEmailText(from: html)
                    guard !title.isEmpty else { continue }

                    let item = SearchItem(
                        id: "outlook:" + fileURL.path,
                        title: title,
                        subtitle: "Outlook Email • " + snippet.prefix(60),
                        fileURL: fileURL,
                        kind: .email,
                        modificationDate: modDate,
                        addedDate: nil,
                        fileSize: size,
                        authorOrSender: "Outlook Mailbox",
                        isOutlookItem: true,
                        matchSnippet: snippet
                    )
                    items.append(item)
                }
            }

            // Handle Email Attachments (PDFs, docs sent via email)
            if path.contains("Attachments") && (fileURL.pathExtension.lowercased() == "pdf" || fileURL.pathExtension.lowercased() == "docx" || fileURL.pathExtension.lowercased() == "xlsx") {
                let filename = fileURL.lastPathComponent
                let cleanTitle = cleanAttachmentName(filename)

                let item = SearchItem(
                    id: "outlook-attach:" + fileURL.path,
                    title: cleanTitle,
                    subtitle: "Outlook Email Attachment • " + fileURL.pathExtension.uppercased(),
                    fileURL: fileURL,
                    kind: .document,
                    modificationDate: modDate,
                    addedDate: nil,
                    fileSize: size,
                    authorOrSender: "Email Attachment",
                    isOutlookItem: true,
                    matchSnippet: filename
                )
                items.append(item)
            }
        }
    }

    // MARK: - Apple Mail (.emlx)
    private func indexAppleMail(at mailURL: URL, into items: inout [SearchItem]) {
        guard let enumerator = fileManager.enumerator(
            at: mailURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            if count >= 200 { break }
            guard fileURL.pathExtension.lowercased() == "emlx" else { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let modDate = values.contentModificationDate ?? Date()
            let size = Int64(values.fileSize ?? 0)

            if let content = try? String(contentsOf: fileURL, encoding: .ascii) {
                let subject = extractHeader("Subject", from: content) ?? "Apple Mail Message"
                let from = extractHeader("From", from: content) ?? "Apple Mail"

                let item = SearchItem(
                    id: "mail:" + fileURL.path,
                    title: subject,
                    subtitle: "Apple Mail • From: " + from,
                    fileURL: fileURL,
                    kind: .email,
                    modificationDate: modDate,
                    addedDate: nil,
                    fileSize: size,
                    authorOrSender: from,
                    isOutlookItem: false,
                    matchSnippet: subject
                )
                items.append(item)
                count += 1
            }
        }
    }

    // MARK: - Legacy Outlook (.olk15Message)
    private func indexLegacyOutlook(at dirURL: URL, into items: inout [SearchItem]) {
        guard let enumerator = fileManager.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var count = 0
        for case let fileURL as URL in enumerator {
            if count >= 100 { break }
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "olk15message" || ext == "eml" else { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let filename = (fileURL.lastPathComponent as NSString).deletingPathExtension
            let modDate = values.contentModificationDate ?? Date()

            let item = SearchItem(
                id: "legacy-outlook:" + fileURL.path,
                title: filename.isEmpty ? "Outlook Email" : filename,
                subtitle: "Legacy Outlook Message",
                fileURL: fileURL,
                kind: .email,
                modificationDate: modDate,
                addedDate: nil,
                fileSize: Int64(values.fileSize ?? 0),
                authorOrSender: "Outlook",
                isOutlookItem: true,
                matchSnippet: filename
            )
            items.append(item)
            count += 1
        }
    }

    // MARK: - Gzip Decompressor & Clean Text Parser
    private func decompressGzip(data: Data) -> Data? {
        guard data.count > 2 && data[0] == 0x1f && data[1] == 0x8b else { return nil }

        var stream = z_stream()
        // 31 tells zlib to auto-detect gzip header
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var decompressed = Data(capacity: min(data.count * 6, 250000))
        let chunkSize = 16384
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        data.withUnsafeBytes { rawBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: rawBuffer.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)

            repeat {
                buffer.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = outBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    let status = inflate(&stream, Z_NO_FLUSH)
                    if status == Z_OK || status == Z_STREAM_END {
                        let written = chunkSize - Int(stream.avail_out)
                        decompressed.append(outBuffer.bindMemory(to: UInt8.self).baseAddress!, count: written)
                    }
                }
            } while stream.avail_out == 0
        }
        return decompressed
    }

    private func extractCleanEmailText(from html: String) -> (title: String, snippet: String) {
        var title = ""
        // Check HTML title
        if let titleRange = html.range(of: "(?<=<title>).*?(?=</title>)", options: .regularExpression) {
            title = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Clean HTML tags and entities
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let words = stripped.components(separatedBy: .whitespacesAndNewlines).filter {
            !$0.isEmpty && !$0.contains("&nbsp") && !$0.contains("&#") && !$0.contains("@media") && !$0.contains("width:")
        }

        let snippet = words.prefix(40).joined(separator: " ")
        if title.isEmpty || title.count < 3 {
            title = words.prefix(8).joined(separator: " ")
        }

        if title.count > 60 {
            title = String(title.prefix(60)) + "..."
        }

        return (title, snippet)
    }

    private func extractHeader(_ header: String, from emailContent: String) -> String? {
        let pattern = "(?m)^\(header):\\s*(.*)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: emailContent, options: [], range: NSRange(location: 0, length: min(emailContent.count, 2000))) {
            if let range = Range(match.range(at: 1), in: emailContent) {
                return String(emailContent[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func cleanAttachmentName(_ filename: String) -> String {
        // Strip trailing [id] tags often added by Outlook cache
        var name = filename
        if let bracketRange = name.range(of: "\\[\\d+\\]\\.", options: .regularExpression) {
            name.removeSubrange(bracketRange.lowerBound..<name.index(before: bracketRange.upperBound))
        }
        return name
    }
}
