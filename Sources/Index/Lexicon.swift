import Foundation

/// All the "vocabulary knowledge" in one place: typos, synonyms, type words, stop words.
enum Lexicon {

    static let misspellings: [String: String] = [
        "recipt": "receipt", "reciept": "receipt", "receit": "receipt", "recipet": "receipt", "recept": "receipt",
        "invoce": "invoice", "invioce": "invoice", "invoive": "invoice", "inovice": "invoice", "invoic": "invoice",
        "statment": "statement", "statmnt": "statement", "stetement": "statement",
        "perscription": "prescription", "perscrip": "prescription", "prescripton": "prescription",
        "apointment": "appointment", "apointmnt": "appointment", "apppointment": "appointment", "appoitment": "appointment",
        "docter": "doctor", "docotr": "doctor",
        "screenhot": "screenshot", "screnshot": "screenshot", "scrnshot": "screenshot", "screeshot": "screenshot",
        "whatspp": "whatsapp", "whatsap": "whatsapp", "watsapp": "whatsapp", "whatsup": "whatsapp",
        "telgram": "telegram", "telegrm": "telegram",
        "downlod": "download", "downlaod": "download", "dowload": "download",
        "calender": "calendar", "calander": "calendar",
        "quotaion": "quotation", "qoutation": "quotation", "quatation": "quotation", "quotatoin": "quotation",
        "certifcate": "certificate", "certificat": "certificate", "sertificate": "certificate",
        "calibraton": "calibration", "calibartion": "calibration",
        "pruchase": "purchase", "purchse": "purchase", "purhcase": "purchase",
        "agrement": "agreement", "agreemnt": "agreement",
        "insurence": "insurance", "insuarnce": "insurance",
        "adress": "address", "adhar": "aadhaar", "aadhar": "aadhaar", "aadhaar": "aadhaar"
    ]

    static let stopwords: Set<String> = [
        "the", "a", "an", "of", "for", "from", "that", "this", "my", "me", "i", "to", "in", "on", "at",
        "and", "find", "show", "get", "where", "is", "was", "file", "files", "document", "documents",
        "open", "launch", "please", "with", "about", "which", "one", "some", "all", "dated", "since"
    ]

    /// Words that mean "this file type". Removed from the text query, used as a filter (with fallback).
    static let extensionWords: [String: [String]] = [
        "pdf": ["pdf"],
        "doc": ["docx", "doc"], "docx": ["docx", "doc"], "word": ["docx", "doc"],
        "excel": ["xlsx", "xls", "csv"], "xlsx": ["xlsx", "xls", "csv"], "xls": ["xlsx", "xls", "csv"],
        "csv": ["csv"], "spreadsheet": ["xlsx", "xls", "csv", "numbers"], "sheet": ["xlsx", "xls", "csv", "numbers"],
        "powerpoint": ["pptx", "ppt", "key"], "ppt": ["pptx", "ppt", "key"], "pptx": ["pptx", "ppt", "key"],
        "presentation": ["pptx", "ppt", "key"], "slides": ["pptx", "ppt", "key"],
        "photo": ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"], "photos": ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"],
        "picture": ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"], "pictures": ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"],
        "image": ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"], "images": ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"],
        "jpg": ["jpg", "jpeg"], "jpeg": ["jpg", "jpeg"], "png": ["png"], "heic": ["heic"],
        "zip": ["zip"], "txt": ["txt"],
        "video": ["mp4", "mov", "m4v", "avi", "mkv"], "videos": ["mp4", "mov", "m4v", "avi", "mkv"],
        "audio": ["mp3", "m4a", "wav", "aac"], "music": ["mp3", "m4a", "wav", "aac"]
    ]

    static let kindWords: [String: SearchItemKind] = [
        "email": .email, "emails": .email, "e-mail": .email, "mail": .email, "mails": .email, "outlook": .email,
        "screenshot": .screenshot, "screenshots": .screenshot, "screengrab": .screenshot, "snapshot": .screenshot,
        "folder": .folder, "folders": .folder, "directory": .folder
    ]

    /// word -> index source name
    static let sourceWords: [String: [String]] = [
        "whatsapp": ["whatsapp"], "telegram": ["telegram"], "imessage": ["messages"],
        "attachment": ["messages", "whatsapp", "telegram", "mail-attachment", "outlook-attachment"],
        "attachments": ["messages", "whatsapp", "telegram", "mail-attachment", "outlook-attachment"]
    ]

    static let downloadWords: Set<String> = ["download", "downloads", "downloaded"]
    static let appWords: Set<String> = ["app", "apps", "application", "applications"]
    static let contactWords: Set<String> = ["contact", "contacts"]
    static let calendarWords: Set<String> = ["calendar", "appointment", "appointments", "event", "events"]

    /// Words that are equivalent in a normal person's head. Used only in the widened (tier 2) search.
    static let synonymGroups: [[String]] = [
        ["bill", "invoice", "statement", "receipt", "challan"],
        ["quote", "quotation", "proforma", "estimate"],
        ["photo", "picture", "image", "pic", "img"],
        ["resume", "cv", "biodata"],
        ["agreement", "contract"],
        ["certificate", "cert"],
        ["purchase", "po", "order"],
        ["salary", "payslip", "payroll"],
        ["tax", "gst", "itr", "tds"],
        ["insurance", "policy"],
        ["passport", "visa"],
        ["report", "summary"]
    ]

    static let synonymIndex: [String: [String]] = {
        var map: [String: [String]] = [:]
        for group in synonymGroups {
            for word in group {
                map[word, default: []].append(contentsOf: group.filter { $0 != word })
            }
        }
        return map
    }()

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()[]{}<>\"'`"))
    }
}
