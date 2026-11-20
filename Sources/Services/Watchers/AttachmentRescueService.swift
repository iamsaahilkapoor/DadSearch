import Foundation

public final class AttachmentRescueService: @unchecked Sendable {
    public static let shared = AttachmentRescueService()

    private let fileManager = FileManager.default
    private let rescuedDir: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DadSearch/RescuedAttachments", isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.rescuedDir = appSupport
    }

    public func rescueAttachment(from sourceURL: URL, sourceApp: String = "Email Attachment") -> URL? {
        guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }

        let filename = sourceURL.lastPathComponent
        // Clean out temporary bracket prefixes/suffixes
        let cleanName = filename.replacingOccurrences(of: "\\[\\d+\\]", with: "", options: .regularExpression)
        let destinationURL = rescuedDir.appendingPathComponent(cleanName)

        // If already rescued, return existing copy
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        // APFS Clone (copy-on-write, consumes 0 bytes of extra disk space until modified)
        let cloneResult = copyfile(sourceURL.path, destinationURL.path, nil, copyfile_flags_t(COPYFILE_CLONE | COPYFILE_ALL))
        if cloneResult == 0 {
            return destinationURL
        } else {
            // Fallback standard copy if not on same APFS volume
            try? fileManager.copyItem(at: sourceURL, to: destinationURL)
            return fileManager.fileExists(atPath: destinationURL.path) ? destinationURL : sourceURL
        }
    }
}
