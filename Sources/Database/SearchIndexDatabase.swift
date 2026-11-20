import Foundation
import SQLite3

public struct IndexedDocument: Sendable {
    public let id: String
    public let title: String
    public let content: String
    public let subtitle: String
    public let path: String
    public let whereFroms: String
    public let sourceApp: String
    public let kind: String
    public let dateAdded: Date
    public let modDate: Date
    public let aliases: String
    public let fileSize: Int64

    public init(
        id: String,
        title: String,
        content: String = "",
        subtitle: String = "",
        path: String = "",
        whereFroms: String = "",
        sourceApp: String = "",
        kind: String = "other",
        dateAdded: Date = Date(),
        modDate: Date = Date(),
        aliases: String = "",
        fileSize: Int64 = 0
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.subtitle = subtitle
        self.path = path
        self.whereFroms = whereFroms
        self.sourceApp = sourceApp
        self.kind = kind
        self.dateAdded = dateAdded
        self.modDate = modDate
        self.aliases = aliases
        self.fileSize = fileSize
    }
}

public final class SearchIndexDatabase: @unchecked Sendable {
    public static let shared = SearchIndexDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.saahil.DadSearch.dbQueue", qos: .userInitiated)

    public init() {
        openDatabase()
        createTables()
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DadSearch", isDirectory: true)
        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        let dbURL = appSupport.appendingPathComponent("DadSearchIndex.sqlite")

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("DadSearch: Failed to open SQLite database at \(dbURL.path)")
        }
    }

    private func createTables() {
        queue.sync {
            guard let db = db else { return }

            // Metadata and document backing table
            let createDocsSql = """
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                content TEXT,
                subtitle TEXT,
                path TEXT,
                whereFroms TEXT,
                sourceApp TEXT,
                kind TEXT,
                dateAdded REAL,
                modDate REAL,
                aliases TEXT,
                fileSize INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_docs_date ON documents(dateAdded DESC);
            CREATE INDEX IF NOT EXISTS idx_docs_kind ON documents(kind);
            """
            sqlite3_exec(db, createDocsSql, nil, nil, nil)

            // FTS5 Virtual Table with trigram tokenizer
            let createFtsSql = """
            CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
                title,
                content,
                subtitle,
                whereFroms,
                sourceApp,
                aliases,
                content='documents',
                content_rowid='rowid',
                tokenize='trigram'
            );
            """
            sqlite3_exec(db, createFtsSql, nil, nil, nil)

            // Triggers to keep FTS5 in sync with documents table
            let triggersSql = """
            CREATE TRIGGER IF NOT EXISTS docs_ai AFTER INSERT ON documents BEGIN
              INSERT INTO search_fts(rowid, title, content, subtitle, whereFroms, sourceApp, aliases)
              VALUES (new.rowid, new.title, new.content, new.subtitle, new.whereFroms, new.sourceApp, new.aliases);
            END;
            CREATE TRIGGER IF NOT EXISTS docs_ad AFTER DELETE ON documents BEGIN
              INSERT INTO search_fts(search_fts, rowid, title, content, subtitle, whereFroms, sourceApp, aliases)
              VALUES('delete', old.rowid, old.title, old.content, old.subtitle, old.whereFroms, old.sourceApp, old.aliases);
            END;
            CREATE TRIGGER IF NOT EXISTS docs_au AFTER UPDATE ON documents BEGIN
              INSERT INTO search_fts(search_fts, rowid, title, content, subtitle, whereFroms, sourceApp, aliases)
              VALUES('delete', old.rowid, old.title, old.content, old.subtitle, old.whereFroms, old.sourceApp, old.aliases);
              INSERT INTO search_fts(rowid, title, content, subtitle, whereFroms, sourceApp, aliases)
              VALUES (new.rowid, new.title, new.content, new.subtitle, new.whereFroms, new.sourceApp, new.aliases);
            END;
            """
            sqlite3_exec(db, triggersSql, nil, nil, nil)
        }
    }

    public func upsert(document doc: IndexedDocument) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = """
            INSERT INTO documents (id, title, content, subtitle, path, whereFroms, sourceApp, kind, dateAdded, modDate, aliases, fileSize)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title=excluded.title,
                content=excluded.content,
                subtitle=excluded.subtitle,
                path=excluded.path,
                whereFroms=excluded.whereFroms,
                sourceApp=excluded.sourceApp,
                kind=excluded.kind,
                dateAdded=excluded.dateAdded,
                modDate=excluded.modDate,
                aliases=CASE WHEN documents.aliases IS NOT NULL AND length(documents.aliases) > 0 THEN documents.aliases ELSE excluded.aliases END,
                fileSize=excluded.fileSize;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (doc.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (doc.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (doc.content as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (doc.subtitle as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 5, (doc.path as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 6, (doc.whereFroms as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 7, (doc.sourceApp as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 8, (doc.kind as NSString).utf8String, -1, nil)
                sqlite3_bind_double(stmt, 9, doc.dateAdded.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 10, doc.modDate.timeIntervalSince1970)
                sqlite3_bind_text(stmt, 11, (doc.aliases as NSString).utf8String, -1, nil)
                sqlite3_bind_int64(stmt, 12, doc.fileSize)

                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func search(query: String, category: SearchCategoryFilter? = nil, limit: Int = 100) -> [SearchItem] {
        return queue.sync {
            guard let db = db else { return [] }

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

            // If empty query, return newest files
            if trimmed.isEmpty {
                return fetchRecentDocuments(category: category, limit: limit)
            }

            // Split into multi-word search tokens for FTS5
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard !tokens.isEmpty else { return [] }

            // Trigram match: wrap each token in quotes for literal substring matching in FTS5
            let ftsMatchClause = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " AND ")

            var sql = """
            SELECT d.id, d.title, d.subtitle, d.path, d.whereFroms, d.sourceApp, d.kind, d.dateAdded, d.modDate, d.fileSize, bm25(search_fts) as rank
            FROM search_fts f
            JOIN documents d ON d.rowid = f.rowid
            WHERE search_fts MATCH ?
            """

            var kindFilter: String? = nil
            if let cat = category, cat != .all && cat != .recent {
                switch cat {
                case .documents: kindFilter = "document"
                case .downloads: kindFilter = "download"
                case .screenshots: kindFilter = "screenshot"
                case .chatAttachments: kindFilter = "chatAttachment"
                case .emails: kindFilter = "email"
                case .apps: kindFilter = "application"
                case .contacts: kindFilter = "contact"
                default: break
                }
            }

            if kindFilter != nil {
                sql += " AND d.kind = ?"
            }

            sql += " ORDER BY rank ASC, d.dateAdded DESC LIMIT ?"

            var stmt: OpaquePointer?
            var results: [SearchItem] = []

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (ftsMatchClause as NSString).utf8String, -1, nil)
                var bindIdx: Int32 = 2
                if let kf = kindFilter {
                    sqlite3_bind_text(stmt, bindIdx, (kf as NSString).utf8String, -1, nil)
                    bindIdx += 1
                }
                sqlite3_bind_int(stmt, bindIdx, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let item = parseRow(stmt: stmt) {
                        results.append(item)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return results
        }
    }

    public func fetchRecentDocuments(category: SearchCategoryFilter? = nil, limit: Int = 50) -> [SearchItem] {
        guard let db = db else { return [] }

        var sql = "SELECT id, title, subtitle, path, whereFroms, sourceApp, kind, dateAdded, modDate, fileSize, 0.0 as rank FROM documents"
        var kindFilter: String? = nil

        if let cat = category, cat != .all && cat != .recent {
            switch cat {
            case .documents: kindFilter = "document"
            case .downloads: kindFilter = "download"
            case .screenshots: kindFilter = "screenshot"
            case .chatAttachments: kindFilter = "chatAttachment"
            case .emails: kindFilter = "email"
            case .apps: kindFilter = "application"
            case .contacts: kindFilter = "contact"
            default: break
            }
        }

        if kindFilter != nil {
            sql += " WHERE kind = ?"
        }

        sql += " ORDER BY dateAdded DESC LIMIT ?"

        var stmt: OpaquePointer?
        var results: [SearchItem] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            var bindIdx: Int32 = 1
            if let kf = kindFilter {
                sqlite3_bind_text(stmt, bindIdx, (kf as NSString).utf8String, -1, nil)
                bindIdx += 1
            }
            sqlite3_bind_int(stmt, bindIdx, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = parseRow(stmt: stmt) {
                    results.append(item)
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    public func fetchTodayArrivals(limit: Int = 30) -> [SearchItem] {
        return queue.sync {
            guard let db = db else { return [] }
            let startOfToday = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

            let sql = """
            SELECT id, title, subtitle, path, whereFroms, sourceApp, kind, dateAdded, modDate, fileSize, 0.0 as rank
            FROM documents
            WHERE dateAdded >= ?
            ORDER BY dateAdded DESC
            LIMIT ?
            """

            var stmt: OpaquePointer?
            var results: [SearchItem] = []

            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, startOfToday)
                sqlite3_bind_int(stmt, 2, Int32(limit))

                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let item = parseRow(stmt: stmt) {
                        results.append(item)
                    }
                }
            }
            sqlite3_finalize(stmt)
            return results
        }
    }

    public func recordAlias(query: String, forId id: String) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return }

            let sql = """
            UPDATE documents
            SET aliases = CASE
                WHEN aliases IS NULL OR length(aliases) = 0 THEN ?
                WHEN instr(aliases, ?) > 0 THEN aliases
                ELSE aliases || ' ' || ?
            END
            WHERE id = ?;
            """

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, (trimmed as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 2, (trimmed as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 3, (trimmed as NSString).utf8String, -1, nil)
                sqlite3_bind_text(stmt, 4, (id as NSString).utf8String, -1, nil)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    public func count(kind: SearchItemKind? = nil) -> Int {
        return queue.sync {
            guard let db = db else { return 0 }
            var sql = "SELECT count(*) FROM documents"
            if let k = kind {
                sql += " WHERE kind = '\(k.rawValue)'"
            }
            var stmt: OpaquePointer?
            var result = 0
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    result = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    private func parseRow(stmt: OpaquePointer?) -> SearchItem? {
        guard let stmt = stmt else { return nil }

        let id = String(cString: sqlite3_column_text(stmt, 0))
        let title = String(cString: sqlite3_column_text(stmt, 1))
        let subtitle = sqlite3_column_text(stmt, 2) != nil ? String(cString: sqlite3_column_text(stmt, 2)) : ""
        let path = sqlite3_column_text(stmt, 3) != nil ? String(cString: sqlite3_column_text(stmt, 3)) : ""
        let whereFroms = sqlite3_column_text(stmt, 4) != nil ? String(cString: sqlite3_column_text(stmt, 4)) : ""
        let sourceApp = sqlite3_column_text(stmt, 5) != nil ? String(cString: sqlite3_column_text(stmt, 5)) : ""
        let kindStr = sqlite3_column_text(stmt, 6) != nil ? String(cString: sqlite3_column_text(stmt, 6)) : "other"
        let dateAddedTimestamp = sqlite3_column_double(stmt, 7)
        let modTimestamp = sqlite3_column_double(stmt, 8)
        let fileSize = sqlite3_column_int64(stmt, 9)
        let rank = sqlite3_column_double(stmt, 10)

        let dateAdded = Date(timeIntervalSince1970: dateAddedTimestamp)
        let modDate = Date(timeIntervalSince1970: modTimestamp)
        let fileURL = path.isEmpty ? nil : URL(fileURLWithPath: path)

        let kind = SearchItemKind(rawValue: kindStr) ?? .other

        // Enrich subtitle with source domain or app if available
        var finalSubtitle = subtitle
        if !whereFroms.isEmpty && !subtitle.contains(whereFroms) {
            finalSubtitle = "\(whereFroms) • \(subtitle)"
        } else if !sourceApp.isEmpty && !subtitle.contains(sourceApp) {
            finalSubtitle = "\(sourceApp) • \(subtitle)"
        }

        return SearchItem(
            id: id,
            title: title,
            subtitle: finalSubtitle,
            fileURL: fileURL,
            kind: kind,
            modificationDate: modDate,
            addedDate: dateAdded,
            fileSize: fileSize > 0 ? fileSize : nil,
            authorOrSender: sourceApp.isEmpty ? nil : sourceApp,
            isOutlookItem: kind == .email && path.contains("Outlook"),
            matchSnippet: whereFroms.isEmpty ? nil : "Source: \(whereFroms)",
            score: -rank * 10.0 // FTS5 bm25 produces negative scores where smaller is better
        )
    }
}
