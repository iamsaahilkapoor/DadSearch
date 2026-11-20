import Foundation
import AppKit

@MainActor
public final class CoverageHealthService: ObservableObject {
    public static let shared = CoverageHealthService()

    @Published public var hasFullDiskAccess: Bool = false
    @Published public var indexedFileCount: Int = 0
    @Published public var indexedEmailCount: Int = 0
    @Published public var lastSyncDate: Date? = nil

    private init() {
        checkHealth()
    }

    public func checkHealth() {
        // Test reading Mail directory (requires Full Disk Access)
        let mailPath = NSHomeDirectory() + "/Library/Mail"
        self.hasFullDiskAccess = FileManager.default.isReadableFile(atPath: mailPath)

        // Read counts from local SQLite database
        self.indexedFileCount = SearchIndexDatabase.shared.count()
        self.indexedEmailCount = SearchIndexDatabase.shared.count(kind: .email)
        self.lastSyncDate = Date()
    }

    public func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
