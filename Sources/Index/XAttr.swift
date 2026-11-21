import Foundation

/// Reads the hidden "where did this come from" metadata macOS attaches to downloads.
enum XAttr {
    static func data(_ path: String, _ name: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(path, name, &buffer, size, 0, XATTR_NOFOLLOW)
        guard read > 0 else { return nil }
        return Data(buffer.prefix(read))
    }

    /// kMDItemWhereFroms: for browser downloads the page/file URL; for Mail attachments usually sender + message.
    static func whereFroms(_ path: String) -> [String] {
        guard let d = data(path, "com.apple.metadata:kMDItemWhereFroms"),
              let obj = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil) as? [String]
        else { return [] }
        return obj
    }

    /// Name of the app that downloaded the file ("Safari", "Google Chrome", "WhatsApp"...).
    static func quarantineAgent(_ path: String) -> String? {
        guard let d = data(path, "com.apple.quarantine"), let s = String(data: d, encoding: .utf8) else { return nil }
        let parts = s.split(separator: ";", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let agent = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        return agent.isEmpty ? nil : agent
    }

    /// One searchable string: "Google Chrome airtel.in https://www.airtel.in/bill/..."
    static func originText(for path: String) -> String {
        var pieces: [String] = []
        if let agent = quarantineAgent(path) { pieces.append(agent) }
        for from in whereFroms(path).prefix(3) {
            if let host = URL(string: from)?.host { pieces.append(host) }
            pieces.append(String(from.prefix(160)))
        }
        return pieces.joined(separator: " ")
    }
}
