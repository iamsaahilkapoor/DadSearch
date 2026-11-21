import Foundation
import AppKit

public enum SearchItemKind: String, Codable, Sendable, CaseIterable {
    case document
    case download
    case email
    case image
    case archive
    case screenshot
    case chatAttachment
    case application
    case contact
    case calendarEvent
    case note
    case folder
    case other

    public var displayName: String {
        switch self {
        case .document: return "Document"
        case .download: return "Download"
        case .email: return "Email Message"
        case .image: return "Image / Photo"
        case .archive: return "Zip / Archive"
        case .screenshot: return "Screenshot"
        case .chatAttachment: return "Chat Attachment"
        case .application: return "Application"
        case .contact: return "Contact"
        case .calendarEvent: return "Calendar Event"
        case .note: return "Note"
        case .folder: return "Folder"
        case .other: return "File"
        }
    }

    public var systemImage: String {
        switch self {
        case .document: return "doc.text.fill"
        case .download: return "arrow.down.circle.fill"
        case .email: return "envelope.fill"
        case .image: return "photo.fill"
        case .archive: return "doc.zipper"
        case .screenshot: return "camera.viewfinder"
        case .chatAttachment: return "bubble.left.and.bubble.right.fill"
        case .application: return "app.fill"
        case .contact: return "person.crop.circle.fill"
        case .calendarEvent: return "calendar"
        case .note: return "note.text"
        case .folder: return "folder.fill"
        case .other: return "doc.fill"
        }
    }

    public var accentColorName: String {
        switch self {
        case .document: return "blue"
        case .download: return "green"
        case .email: return "indigo"
        case .image: return "purple"
        case .archive: return "orange"
        case .screenshot: return "teal"
        case .chatAttachment: return "pink"
        case .application: return "cyan"
        case .contact: return "orange"
        case .calendarEvent: return "red"
        case .note: return "yellow"
        case .folder: return "blue"
        case .other: return "gray"
        }
    }
}

public struct SearchItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let fileURL: URL?
    public let kind: SearchItemKind
    public let modificationDate: Date
    public let addedDate: Date?
    public let fileSize: Int64?
    public let authorOrSender: String?
    public let isOutlookItem: Bool
    public let matchSnippet: String?
    public var score: Double
    /// Where the item came from: file, outlook, outlook-attachment, applemail, messages, whatsapp, telegram, mail-attachment, spotlight, app ...
    public let source: String
    /// Opaque provider reference (e.g. Outlook record id used to open the message).
    public let ref: String
    public let isHidden: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        fileURL: URL?,
        kind: SearchItemKind,
        modificationDate: Date,
        addedDate: Date? = nil,
        fileSize: Int64? = nil,
        authorOrSender: String? = nil,
        isOutlookItem: Bool = false,
        matchSnippet: String? = nil,
        score: Double = 0.0,
        source: String = "",
        ref: String = "",
        isHidden: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.fileURL = fileURL
        self.kind = kind
        self.modificationDate = modificationDate
        self.addedDate = addedDate
        self.fileSize = fileSize
        self.authorOrSender = authorOrSender
        self.isOutlookItem = isOutlookItem
        self.matchSnippet = matchSnippet
        self.score = score
        self.source = source
        self.ref = ref
        self.isHidden = isHidden
    }

    public var formattedDate: String {
        let dateToFormat = addedDate ?? modificationDate
        let calendar = Calendar.current
        if calendar.isDateInToday(dateToFormat) {
            let formatter = DateFormatter()
            formatter.dateFormat = "'Today at' h:mm a"
            return formatter.string(from: dateToFormat)
        } else if calendar.isDateInYesterday(dateToFormat) {
            let formatter = DateFormatter()
            formatter.dateFormat = "'Yesterday at' h:mm a"
            return formatter.string(from: dateToFormat)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: dateToFormat)
        }
    }

    public var formattedFileSize: String? {
        guard let fileSize = fileSize, fileSize > 0 else { return nil }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: fileSize)
    }
}
