import Foundation

public final class DownloadsTracker: @unchecked Sendable {
    public static let shared = DownloadsTracker()

    private let fileManager = FileManager.default
    private let downloadsURL: URL

    public init() {
        self.downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    public func fetchRecentDownloads(limit: Int = 50) -> [SearchItem] {
        guard let enumerator = fileManager.enumerator(
            at: downloadsURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .creationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
                .contentTypeKey
            ],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var items: [SearchItem] = []

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [
                .contentModificationDateKey,
                .creationDateKey,
                .fileSizeKey,
                .isRegularFileKey
            ]) else {
                continue
            }

            guard resourceValues.isRegularFile == true else { continue }

            let filename = fileURL.lastPathComponent
            // Ignore system or temporary download partial files (.crdownload, .download, etc.)
            if filename.hasSuffix(".crdownload") || filename.hasSuffix(".download") || filename.hasPrefix(".") {
                continue
            }

            let modDate = resourceValues.contentModificationDate ?? Date()
            let createDate = resourceValues.creationDate ?? modDate
            let size = Int64(resourceValues.fileSize ?? 0)

            let kind = determineKind(for: fileURL)

            let item = SearchItem(
                id: fileURL.path,
                title: filename,
                subtitle: "Downloads Folder • \(fileURL.path)",
                fileURL: fileURL,
                kind: kind,
                modificationDate: modDate,
                addedDate: createDate,
                fileSize: size,
                authorOrSender: nil,
                isOutlookItem: false,
                matchSnippet: nil
            )
            items.append(item)
        }

        // Sort descending by creation/modification date
        items.sort { ($0.addedDate ?? $0.modificationDate) > ($1.addedDate ?? $1.modificationDate) }

        if items.count > limit {
            return Array(items.prefix(limit))
        }
        return items
    }

    private func determineKind(for url: URL) -> SearchItemKind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "numbers", "key", "xls", "xlsx", "csv", "ppt", "pptx":
            return .document
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "webp", "svg":
            return .image
        case "zip", "tar", "gz", "7z", "dmg", "pkg":
            return .archive
        default:
            return .download
        }
    }
}
