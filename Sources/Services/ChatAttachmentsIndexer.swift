import Foundation

public final class ChatAttachmentsIndexer: @unchecked Sendable {
    public static let shared = ChatAttachmentsIndexer()

    private let fileManager = FileManager.default

    public init() {}

    private struct ChatSource {
        let appName: String
        let directory: URL
        let recursive: Bool
    }

    private var chatSources: [ChatSource] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var sources: [ChatSource] = []

        // 1. Apple Messages Attachments
        let messagesAttachments = home.appendingPathComponent("Library/Messages/Attachments")
        if fileManager.fileExists(atPath: messagesAttachments.path) {
            sources.append(ChatSource(appName: "iMessage", directory: messagesAttachments, recursive: true))
        }

        // 2. Telegram Desktop / Caches
        let telegramGroup = home.appendingPathComponent("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram")
        if fileManager.fileExists(atPath: telegramGroup.path) {
            sources.append(ChatSource(appName: "Telegram", directory: telegramGroup, recursive: true))
        }
        let telegramDownloads = home.appendingPathComponent("Downloads/Telegram Desktop")
        if fileManager.fileExists(atPath: telegramDownloads.path) {
            sources.append(ChatSource(appName: "Telegram", directory: telegramDownloads, recursive: false))
        }

        // 3. WhatsApp Desktop
        let whatsappContainer = home.appendingPathComponent("Library/Containers/net.whatsapp.WhatsApp/Data/Library/Application Support/WhatsApp")
        if fileManager.fileExists(atPath: whatsappContainer.path) {
            sources.append(ChatSource(appName: "WhatsApp", directory: whatsappContainer, recursive: true))
        }

        // 4. Apple Mail Downloads
        let mailDownloads = home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        if fileManager.fileExists(atPath: mailDownloads.path) {
            sources.append(ChatSource(appName: "Mail Attachment", directory: mailDownloads, recursive: true))
        }

        return sources
    }

    public func fetchRecentChatAttachments(limit: Int = 50, keyword: String = "") -> [SearchItem] {
        var results: [SearchItem] = []
        let lowerKeyword = keyword.lowercased()

        for source in chatSources {
            let options: FileManager.DirectoryEnumerationOptions = source.recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            guard let enumerator = fileManager.enumerator(
                at: source.directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey
                ],
                options: options
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                if results.count >= limit * 2 { break }

                let filename = fileURL.lastPathComponent
                // Skip system sqlite or database files
                if filename.hasSuffix(".db") || filename.hasSuffix(".sqlite") || filename.hasSuffix(".plist") || filename.hasPrefix(".") {
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey
                ]), values.isRegularFile == true else {
                    continue
                }

                let lowerName = filename.lowercased()
                if !lowerKeyword.isEmpty && !lowerName.contains(lowerKeyword) {
                    continue
                }

                let modDate = values.contentModificationDate ?? Date()
                let createDate = values.creationDate ?? modDate
                let size = Int64(values.fileSize ?? 0)

                let item = SearchItem(
                    id: fileURL.path,
                    title: filename,
                    subtitle: "\(source.appName) • " + (fileURL.path as NSString).abbreviatingWithTildeInPath,
                    fileURL: fileURL,
                    kind: .chatAttachment,
                    modificationDate: modDate,
                    addedDate: createDate,
                    fileSize: size,
                    authorOrSender: source.appName,
                    isOutlookItem: false,
                    matchSnippet: nil
                )
                results.append(item)
            }
        }

        // Sort descending by date
        results.sort { ($0.addedDate ?? $0.modificationDate) > ($1.addedDate ?? $1.modificationDate) }
        return Array(results.prefix(limit))
    }
}
