import Foundation
import CoreServices

public final class ArrivalRadarService: @unchecked Sendable {
    public static let shared = ArrivalRadarService()

    private init() {}

    public struct RadarMetadata: Sendable {
        public let dateAdded: Date
        public let whereFroms: [String]
        public let primaryDomain: String?
        public let downloadingApp: String?
    }

    public func extractMetadata(for url: URL) -> RadarMetadata {
        var dateAdded = Date()
        var whereFroms: [String] = []
        var primaryDomain: String? = nil
        var downloadingApp: String? = nil

        // 1. Fetch kMDItemWhereFroms and kMDItemDateAdded using MDItem
        if let mdItem = MDItemCreate(kCFAllocatorDefault, url.path as CFString) {
            if let dateAddedRef = MDItemCopyAttribute(mdItem, kMDItemDateAdded) {
                dateAdded = dateAddedRef as? Date ?? Date()
            } else if let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
                dateAdded = resourceValues.creationDate ?? resourceValues.contentModificationDate ?? Date()
            }

            if let whereFromsRef = MDItemCopyAttribute(mdItem, kMDItemWhereFroms) as? [String] {
                whereFroms = whereFromsRef
                for source in whereFromsRef {
                    if let domain = extractDomain(from: source) {
                        primaryDomain = domain
                        break
                    }
                }
            }
        }

        // 2. Fetch downloading application from com.apple.quarantine extended attribute
        if let quarantineStr = getExtendedAttribute(named: "com.apple.quarantine", at: url) {
            // Quarantine format: flags;timestamp;agent_bundle_id;uuid
            let components = quarantineStr.components(separatedBy: ";")
            if components.count >= 3 {
                let agent = components[2]
                downloadingApp = friendlyAppName(for: agent)
            }
        }

        return RadarMetadata(
            dateAdded: dateAdded,
            whereFroms: whereFroms,
            primaryDomain: primaryDomain,
            downloadingApp: downloadingApp
        )
    }

    private func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return nil
        }
        // Strip www. prefix
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    private func friendlyAppName(for bundleIdentifier: String) -> String {
        let lower = bundleIdentifier.lowercased()
        if lower.contains("chrome") { return "Google Chrome" }
        if lower.contains("safari") { return "Safari" }
        if lower.contains("firefox") { return "Firefox" }
        if lower.contains("whatsapp") { return "WhatsApp" }
        if lower.contains("telegram") { return "Telegram" }
        if lower.contains("outlook") { return "Microsoft Outlook" }
        if lower.contains("mail") { return "Apple Mail" }
        if lower.contains("slack") { return "Slack" }
        return bundleIdentifier
    }

    private func getExtendedAttribute(named name: String, at url: URL) -> String? {
        let maxLen = 1024
        var buffer = [CChar](repeating: 0, count: maxLen)
        let result = getxattr(url.path, name, &buffer, maxLen, 0, 0)
        guard result > 0 else { return nil }
        let bytes = buffer.prefix(result).map { UInt8(bitPattern: $0) }
        let str = String(decoding: bytes, as: UTF8.self)
        return str.trimmingCharacters(in: .controlCharacters)
    }
}
