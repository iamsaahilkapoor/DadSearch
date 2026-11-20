import Foundation
import SQLite3

public final class AppleMailDatabaseReader: @unchecked Sendable {
    public static let shared = AppleMailDatabaseReader()

    private let db = SearchIndexDatabase.shared

    private init() {}

    private var envelopeIndexURL: URL? {
        let home = NSHomeDirectory()
        let paths = [
            home + "/Library/Mail/V10/MailData/Envelope Index",
            home + "/Library/Mail/V9/MailData/Envelope Index"
        ]
        for p in paths {
            if FileManager.default.fileExists(atPath: p) {
                return URL(fileURLWithPath: p)
            }
        }
        return nil
    }

    public func syncAppleMailMessages(limit: Int = 500) {
        guard let url = envelopeIndexURL else { return }

        // Needs Full Disk Access to open Envelope Index
        var mailDB: OpaquePointer?
        guard sqlite3_open_v2(url.path, &mailDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_close(mailDB) }

        let sql = """
        SELECT
            m.ROWID,
            s.subject,
            a.address,
            m.date_received
        FROM messages m
        LEFT JOIN subjects s ON m.subject = s.ROWID
        LEFT JOIN addresses a ON m.sender = a.ROWID
        ORDER BY m.date_received DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(mailDB, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowid = sqlite3_column_int64(stmt, 0)
                let subject = sqlite3_column_text(stmt, 1) != nil ? String(cString: sqlite3_column_text(stmt, 1)) : "Mail Message"
                let sender = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : "Unknown Sender"
                let dateSec = sqlite3_column_double(stmt, 3)

                let dateReceived = Date(timeIntervalSince1970: dateSec)

                let doc = IndexedDocument(
                    id: "applemail:\(rowid)",
                    title: subject,
                    content: "Subject: \(subject) From: \(sender)",
                    subtitle: "Apple Mail • From: \(sender)",
                    path: "",
                    whereFroms: "",
                    sourceApp: "Apple Mail",
                    kind: SearchItemKind.email.rawValue,
                    dateAdded: dateReceived,
                    modDate: dateReceived,
                    aliases: "",
                    fileSize: 0
                )
                db.upsert(document: doc)
            }
        }
        sqlite3_finalize(stmt)
    }
}
