import Foundation

enum KindClassifier {
    static let documentExts: Set<String> = [
        "pdf", "doc", "docx", "txt", "rtf", "pages", "numbers", "key", "xls", "xlsx", "csv", "ppt", "pptx",
        "odt", "ods", "odp", "md", "epub", "tex", "xml", "json", "html", "htm", "log", "eml", "emlx", "msg"
    ]
    static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp", "svg", "bmp", "raw", "cr2", "nef", "dng", "psd"
    ]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "7z", "rar", "dmg", "pkg", "iso"]
    static let videoExts: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv"]

    static func kind(ext: String, name: String, isDirectory: Bool, isPackage: Bool, path: String) -> SearchItemKind {
        if ext == "app" { return .application }
        if isDirectory && !isPackage { return .folder }
        let lowerName = name.lowercased()
        if (imageExts.contains(ext) || videoExts.contains(ext)) &&
            (lowerName.hasPrefix("screenshot") || lowerName.hasPrefix("screen shot") || lowerName.hasPrefix("screen recording") || lowerName.contains("screenshot")) {
            return .screenshot
        }
        if ext == "emlx" || ext == "eml" || ext == "olk15message" { return .email }
        if documentExts.contains(ext) { return .document }
        if imageExts.contains(ext) { return .image }
        if archiveExts.contains(ext) { return .archive }
        if path.contains("/Downloads/") { return .download }
        return .other
    }

    /// Which "place" a path belongs to. Drives chips like "WhatsApp" and "Chat & Attachments".
    static func source(forPath path: String) -> String {
        if path.contains("/Library/Messages/Attachments") { return "messages" }
        let lower = path.lowercased()
        if lower.contains("whatsapp") && lower.contains("/library/") { return "whatsapp" }
        if lower.contains("/telegram desktop/") || (lower.contains("keepcoder") && lower.contains("/library/")) { return "telegram" }
        if lower.contains("mail downloads") { return "mail-attachment" }
        return "file"
    }
}
