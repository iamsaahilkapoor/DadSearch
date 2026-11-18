import Foundation
import AppKit

public final class AppLauncherEngine: @unchecked Sendable {
    public static let shared = AppLauncherEngine()

    private let fileManager = FileManager.default
    private var cachedApps: [SearchItem] = []
    private var lastIndexTime: Date = .distantPast

    private init() {}

    private var appDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications")
        ].filter { fileManager.fileExists(atPath: $0.path) }
    }

    public func fetchApplications(keyword: String = "", limit: Int = 30) -> [SearchItem] {
        // Refresh cache every 5 minutes
        if cachedApps.isEmpty || Date().timeIntervalSince(lastIndexTime) > 300 {
            indexInstalledApps()
        }

        if keyword.isEmpty {
            return Array(cachedApps.prefix(limit))
        }

        let lower = keyword.lowercased()
        let filtered = cachedApps.filter {
            $0.title.lowercased().contains(lower) ||
            $0.subtitle.lowercased().contains(lower)
        }
        return Array(filtered.prefix(limit))
    }

    private func indexInstalledApps() {
        var items: [SearchItem] = []
        var seenBundleIDs = Set<String>()

        for dir in appDirectories {
            guard let enumerator = fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isApplicationKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else {
                continue
            }

            for case let appURL as URL in enumerator {
                guard appURL.pathExtension == "app" else { continue }

                let appName = (appURL.lastPathComponent as NSString).deletingPathExtension
                let bundle = Bundle(url: appURL)
                let bundleID = bundle?.bundleIdentifier ?? appURL.path

                if seenBundleIDs.contains(bundleID) { continue }
                seenBundleIDs.insert(bundleID)

                let modDate = (try? appURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

                let item = SearchItem(
                    id: "app:" + appURL.path,
                    title: appName,
                    subtitle: "Application • " + appURL.path,
                    fileURL: appURL,
                    kind: .application,
                    modificationDate: modDate,
                    addedDate: nil,
                    fileSize: nil,
                    authorOrSender: "Apple / Third-Party",
                    isOutlookItem: false,
                    matchSnippet: nil
                )
                items.append(item)
            }
        }

        items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        self.cachedApps = items
        self.lastIndexTime = Date()
    }
}
