import Foundation

public final class ScreenshotsTracker: @unchecked Sendable {
    public static let shared = ScreenshotsTracker()

    private let fileManager = FileManager.default

    public init() {}

    private var candidateDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let paths = [
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Pictures/Screenshots"),
            home.appendingPathComponent("Pictures")
        ]
        return paths.filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func fetchRecentScreenshots(limit: Int = 50, keyword: String = "") -> [SearchItem] {
        var results: [SearchItem] = []
        let lowerKeyword = keyword.lowercased()

        for dir in candidateDirectories {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey
                ],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                let filename = fileURL.lastPathComponent
                let lowerName = filename.lowercased()

                // Check screenshot pattern
                let isScreenshot = lowerName.hasPrefix("screenshot") ||
                                   lowerName.hasPrefix("screen shot") ||
                                   lowerName.hasPrefix("cleanshot") ||
                                   lowerName.hasPrefix("screen recording") ||
                                   lowerName.contains("screenshot")

                guard isScreenshot else { continue }

                guard let values = try? fileURL.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey
                ]), values.isRegularFile == true else {
                    continue
                }

                if !lowerKeyword.isEmpty && !lowerName.contains(lowerKeyword) {
                    continue
                }

                let createDate = values.creationDate ?? values.contentModificationDate ?? Date()
                let size = Int64(values.fileSize ?? 0)

                let item = SearchItem(
                    id: fileURL.path,
                    title: filename,
                    subtitle: "Screenshot • " + (fileURL.path as NSString).abbreviatingWithTildeInPath,
                    fileURL: fileURL,
                    kind: .screenshot,
                    modificationDate: values.contentModificationDate ?? Date(),
                    addedDate: createDate,
                    fileSize: size,
                    authorOrSender: "Screen Capture",
                    isOutlookItem: false,
                    matchSnippet: nil
                )
                results.append(item)
            }
        }

        results.sort { ($0.addedDate ?? $0.modificationDate) > ($1.addedDate ?? $1.modificationDate) }
        return Array(results.prefix(limit))
    }
}
