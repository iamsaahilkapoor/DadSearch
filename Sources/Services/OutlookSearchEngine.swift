import Foundation

public final class OutlookSearchEngine: @unchecked Sendable {
    public static let shared = OutlookSearchEngine()

    private let fileManager = FileManager.default

    public init() {}

    private var outlookProfileDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let candidates = [
            // Standard Microsoft Outlook 15/16 profiles container
            home.appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles"),
            home.appendingPathComponent("Library/Containers/com.microsoft.Outlook/Data/Library/Caches"),
            home.appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/Outlook")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func searchOutlookMessages(keyword: String, limit: Int = 30) -> [SearchItem] {
        let dirs = outlookProfileDirectories
        guard !dirs.isEmpty else { return [] }

        var results: [SearchItem] = []
        let lower = keyword.lowercased()

        for dir in dirs {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                if results.count >= limit { break }

                let ext = fileURL.pathExtension.lowercased()
                guard ext == "olk15message" || ext == "eml" || ext == "olk14message" else {
                    continue
                }

                guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true else {
                    continue
                }

                let filename = fileURL.lastPathComponent
                let modDate = values.contentModificationDate ?? Date()

                if keyword.isEmpty || filename.localizedCaseInsensitiveContains(lower) {
                    let item = SearchItem(
                        id: fileURL.path,
                        title: cleanOutlookTitle(from: filename),
                        subtitle: "Outlook Cached Message • " + (fileURL.path as NSString).abbreviatingWithTildeInPath,
                        fileURL: fileURL,
                        kind: .email,
                        modificationDate: modDate,
                        addedDate: nil,
                        fileSize: Int64(values.fileSize ?? 0),
                        authorOrSender: "Outlook",
                        isOutlookItem: true,
                        matchSnippet: nil
                    )
                    results.append(item)
                }
            }
        }

        return results
    }

    private func cleanOutlookTitle(from filename: String) -> String {
        let name = (filename as NSString).deletingPathExtension
        if name.count > 40 {
            return String(name.prefix(40)) + "..."
        }
        return name.isEmpty ? "Outlook Email Message" : name
    }
}
