import Foundation
import SQLite3

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct IndexRecord {
    var key: String
    var path: String?
    var name: String
    var kind: SearchItemKind
    var source: String
    var ext: String = ""
    var size: Int64 = 0
    var mtime: Date = Date()
    var added: Date? = nil
    var sender: String = ""
    var origin: String = ""
    var hidden: Bool = false
    var snippet: String = ""
    var ref: String = ""
    /// Text known at crawl time (e.g. an email's subject + preview). File text arrives later via the extractor.
    var body: String = ""
    var needsExtraction: Bool = false
}

struct StoreQuery {
    /// Each inner array is one "term" with its alternatives (typo fixes / synonyms), OR'd together.
    /// Terms are AND'd, unless `matchAny` is set.
    var termGroups: [[String]] = []
    var matchAny = false
    var extensions: [String] = []
    var kinds: [SearchItemKind] = []
    var sources: [String] = []
    var pathContains: String? = nil
    var dateRange: DateInterval? = nil
    var includeHidden = true
    var limit = 300
}

struct StoreHit {
    var id: Int64
    var key: String
    var path: String?
    var name: String
    var kind: SearchItemKind
    var source: String
    var ext: String
    var size: Int64
    var mtime: Date
    var added: Date?
    var sender: String
    var origin: String
    var hidden: Bool
    var snippet: String
    var ref: String
    var bm25: Double
}

private enum Bind {
    case text(String)
    case real(Double)
    case int(Int64)
    case null
}

/// One SQLite file that remembers everything: files, folders, emails, attachments, chat files.
/// Search = one local query (milliseconds), no caps, no live disk scanning.
final class IndexStore: @unchecked Sendable {
    static let shared = IndexStore()

    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    private(set) var usesTrigram = true
    let vocabulary = Vocabulary()
    let isOpen: Bool

    init(path: String? = nil) {
        let dbPath: String
        if let path = path {
            dbPath = path
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DadSearch", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbPath = dir.appendingPathComponent("index-v1.sqlite").path
        }
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        if rc == SQLITE_OK {
            db = handle
            isOpen = true
            sqlite3_busy_timeout(handle, 5000)
            _ = exec("PRAGMA journal_mode=WAL;")
            _ = exec("PRAGMA synchronous=NORMAL;")
            createSchema()
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.loadVocabulary() }
        } else {
            isOpen = false
        }
    }

    deinit {
        if let db = db { sqlite3_close(db) }
    }

    // MARK: - Low-level helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        return st
    }

    private func bind(_ st: OpaquePointer?, _ values: [Bind]) {
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .text(let s): sqlite3_bind_text(st, idx, s, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            case .real(let d): sqlite3_bind_double(st, idx, d)
            case .int(let n): sqlite3_bind_int64(st, idx, n)
            case .null: sqlite3_bind_null(st, idx)
            }
        }
    }

    private func text(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }

    private func date(_ st: OpaquePointer?, _ i: Int32) -> Date? {
        sqlite3_column_type(st, i) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(st, i))
    }

    // MARK: - Schema

    private func createSchema() {
        exec("""
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          key TEXT NOT NULL UNIQUE,
          path TEXT,
          name TEXT NOT NULL,
          kind TEXT NOT NULL,
          source TEXT NOT NULL,
          ext TEXT NOT NULL DEFAULT '',
          size INTEGER NOT NULL DEFAULT 0,
          mtime REAL NOT NULL DEFAULT 0,
          added REAL,
          sender TEXT NOT NULL DEFAULT '',
          origin TEXT NOT NULL DEFAULT '',
          hidden INTEGER NOT NULL DEFAULT 0,
          snippet TEXT NOT NULL DEFAULT '',
          ref TEXT NOT NULL DEFAULT '',
          extracted INTEGER NOT NULL DEFAULT 1
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_items_path ON items(path);")
        exec("CREATE INDEX IF NOT EXISTS idx_items_added ON items(added);")
        exec("CREATE INDEX IF NOT EXISTS idx_items_mtime ON items(mtime);")
        exec("CREATE INDEX IF NOT EXISTS idx_items_source ON items(source);")
        exec("CREATE INDEX IF NOT EXISTS idx_items_pending ON items(extracted);")
        exec("CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);")
        exec("CREATE TABLE IF NOT EXISTS learned(item_key TEXT NOT NULL, term TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(item_key, term));")

        if let mode = getMeta("fts_mode") {
            usesTrigram = (mode == "trigram")
        } else if exec("CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(name, sender, origin, body, learned, tokenize='trigram');") {
            usesTrigram = true
            setMeta("fts_mode", "trigram")
        } else {
            // Very old SQLite without the trigram tokenizer: fall back to word-prefix matching.
            usesTrigram = false
            exec("CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(name, sender, origin, body, learned, prefix='2 3 4');")
            setMeta("fts_mode", "unicode61")
        }
    }

    private func loadVocabulary() {
        locked {
            guard let st = prepare("SELECT name, sender FROM items") else { return }
            defer { sqlite3_finalize(st) }
            while sqlite3_step(st) == SQLITE_ROW {
                vocabulary.add(text(st, 0) + " " + text(st, 1))
            }
        }
    }

    // MARK: - Meta

    func getMeta(_ key: String) -> String? {
        locked {
            guard let st = prepare("SELECT v FROM meta WHERE k=?") else { return nil }
            defer { sqlite3_finalize(st) }
            bind(st, [.text(key)])
            return sqlite3_step(st) == SQLITE_ROW ? text(st, 0) : nil
        }
    }

    func setMeta(_ key: String, _ value: String) {
        locked {
            guard let st = prepare("INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v") else { return }
            defer { sqlite3_finalize(st) }
            bind(st, [.text(key), .text(value)])
            sqlite3_step(st)
        }
    }

    // MARK: - Writing

    func upsert(_ records: [IndexRecord]) {
        guard !records.isEmpty else { return }
        locked {
            exec("BEGIN IMMEDIATE;")
            let up = prepare("""
            INSERT INTO items(key,path,name,kind,source,ext,size,mtime,added,sender,origin,hidden,snippet,ref,extracted)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            ON CONFLICT(key) DO UPDATE SET
              path=excluded.path, name=excluded.name, kind=excluded.kind, source=excluded.source, ext=excluded.ext,
              extracted=CASE WHEN items.mtime=excluded.mtime AND items.size=excluded.size THEN items.extracted ELSE excluded.extracted END,
              size=excluded.size, mtime=excluded.mtime, added=excluded.added, sender=excluded.sender, origin=excluded.origin,
              hidden=excluded.hidden, snippet=excluded.snippet, ref=excluded.ref
            """)
            let findID = prepare("SELECT id FROM items WHERE key=?")
            let ftsExists = prepare("SELECT 1 FROM items_fts WHERE rowid=?")
            let ftsInsert = prepare("INSERT INTO items_fts(rowid,name,sender,origin,body,learned) VALUES(?,?,?,?,?,'')")
            let ftsUpdateMeta = prepare("UPDATE items_fts SET name=?, sender=?, origin=? WHERE rowid=?")
            let ftsUpdateBody = prepare("UPDATE items_fts SET body=? WHERE rowid=?")
            defer {
                [up, findID, ftsExists, ftsInsert, ftsUpdateMeta, ftsUpdateBody].forEach { sqlite3_finalize($0) }
                exec("COMMIT;")
            }

            for r in records {
                sqlite3_reset(up)
                bind(up, [
                    .text(r.key), r.path.map { .text($0) } ?? .null, .text(r.name), .text(r.kind.rawValue), .text(r.source),
                    .text(r.ext), .int(r.size), .real(r.mtime.timeIntervalSince1970),
                    r.added.map { .real($0.timeIntervalSince1970) } ?? .null,
                    .text(r.sender), .text(String(r.origin.prefix(400))), .int(r.hidden ? 1 : 0),
                    .text(String(r.snippet.prefix(400))), .text(r.ref), .int(r.needsExtraction ? 0 : 1)
                ])
                guard sqlite3_step(up) == SQLITE_DONE else { continue }

                sqlite3_reset(findID)
                bind(findID, [.text(r.key)])
                guard sqlite3_step(findID) == SQLITE_ROW else { continue }
                let id = sqlite3_column_int64(findID, 0)

                sqlite3_reset(ftsExists)
                bind(ftsExists, [.int(id)])
                let exists = sqlite3_step(ftsExists) == SQLITE_ROW

                if exists {
                    sqlite3_reset(ftsUpdateMeta)
                    bind(ftsUpdateMeta, [.text(r.name), .text(r.sender), .text(r.origin), .int(id)])
                    sqlite3_step(ftsUpdateMeta)
                    if !r.body.isEmpty {
                        sqlite3_reset(ftsUpdateBody)
                        bind(ftsUpdateBody, [.text(String(r.body.prefix(30_000))), .int(id)])
                        sqlite3_step(ftsUpdateBody)
                    }
                } else {
                    sqlite3_reset(ftsInsert)
                    bind(ftsInsert, [.int(id), .text(r.name), .text(r.sender), .text(r.origin), .text(String(r.body.prefix(30_000)))])
                    sqlite3_step(ftsInsert)
                }
                vocabulary.add(r.name + " " + r.sender)
            }
        }
    }

    func setBody(id: Int64, body: String) {
        locked {
            exec("BEGIN IMMEDIATE;")
            if let st = prepare("UPDATE items_fts SET body=? WHERE rowid=?") {
                bind(st, [.text(String(body.prefix(30_000))), .int(id)])
                sqlite3_step(st)
                sqlite3_finalize(st)
            }
            if let st = prepare("UPDATE items SET extracted=1 WHERE id=?") {
                bind(st, [.int(id)])
                sqlite3_step(st)
                sqlite3_finalize(st)
            }
            exec("COMMIT;")
        }
    }

    func deleteByPath(_ path: String) {
        locked {
            for sql in ["DELETE FROM items_fts WHERE rowid IN (SELECT id FROM items WHERE path=?)",
                        "DELETE FROM items WHERE path=?"] {
                if let st = prepare(sql) {
                    bind(st, [.text(path)])
                    sqlite3_step(st)
                    sqlite3_finalize(st)
                }
            }
        }
    }

    func deleteByPrefix(_ prefix: String) {
        locked {
            let like = prefix.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            for sql in ["DELETE FROM items_fts WHERE rowid IN (SELECT id FROM items WHERE path LIKE ? ESCAPE '\\')",
                        "DELETE FROM items WHERE path LIKE ? ESCAPE '\\'"] {
                if let st = prepare(sql) {
                    bind(st, [.text(like)])
                    sqlite3_step(st)
                    sqlite3_finalize(st)
                }
            }
        }
    }

    /// Remove rows whose file no longer exists (run after a crawl).
    func purgeMissing(sources: [String]) {
        let rows: [(Int64, String)] = locked {
            var out: [(Int64, String)] = []
            let marks = sources.map { _ in "?" }.joined(separator: ",")
            guard let st = prepare("SELECT id, path FROM items WHERE path IS NOT NULL AND source IN (\(marks))") else { return out }
            defer { sqlite3_finalize(st) }
            bind(st, sources.map { .text($0) })
            while sqlite3_step(st) == SQLITE_ROW { out.append((sqlite3_column_int64(st, 0), text(st, 1))) }
            return out
        }
        let missing = rows.filter { access($0.1, F_OK) != 0 }.map { $0.0 }
        deleteIDs(missing)
    }

    /// For connectors (Outlook): delete rows of `source` whose key is not in `keep`.
    func deleteMissing(source: String, keep: Set<String>) {
        let rows: [(Int64, String)] = locked {
            var out: [(Int64, String)] = []
            guard let st = prepare("SELECT id, key FROM items WHERE source=?") else { return out }
            defer { sqlite3_finalize(st) }
            bind(st, [.text(source)])
            while sqlite3_step(st) == SQLITE_ROW { out.append((sqlite3_column_int64(st, 0), text(st, 1))) }
            return out
        }
        deleteIDs(rows.filter { !keep.contains($0.1) }.map { $0.0 })
    }

    private func deleteIDs(_ ids: [Int64]) {
        guard !ids.isEmpty else { return }
        locked {
            exec("BEGIN IMMEDIATE;")
            let a = prepare("DELETE FROM items_fts WHERE rowid=?")
            let b = prepare("DELETE FROM items WHERE id=?")
            for id in ids {
                sqlite3_reset(a); bind(a, [.int(id)]); sqlite3_step(a)
                sqlite3_reset(b); bind(b, [.int(id)]); sqlite3_step(b)
            }
            sqlite3_finalize(a); sqlite3_finalize(b)
            exec("COMMIT;")
        }
    }

    // MARK: - Reading helpers for crawler / extractor / health

    /// key -> (mtime, size) so the crawler can skip unchanged files.
    func signatures(sources: [String], pathPrefix: String? = nil) -> [String: (Double, Int64)] {
        locked {
            var out: [String: (Double, Int64)] = [:]
            let marks = sources.map { _ in "?" }.joined(separator: ",")
            var sql = "SELECT key, mtime, size FROM items WHERE source IN (\(marks))"
            var binds: [Bind] = sources.map { .text($0) }
            if let p = pathPrefix {
                sql += " AND path LIKE ? ESCAPE '\\'"
                binds.append(.text(p.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"))
            }
            guard let st = prepare(sql) else { return out }
            defer { sqlite3_finalize(st) }
            bind(st, binds)
            while sqlite3_step(st) == SQLITE_ROW {
                out[text(st, 0)] = (sqlite3_column_double(st, 1), sqlite3_column_int64(st, 2))
            }
            return out
        }
    }

    func pendingExtraction(limit: Int) -> [(id: Int64, path: String, ext: String, kind: SearchItemKind, size: Int64)] {
        locked {
            var out: [(id: Int64, path: String, ext: String, kind: SearchItemKind, size: Int64)] = []
            guard let st = prepare("""
                SELECT id, path, ext, kind, size FROM items
                WHERE extracted=0 AND path IS NOT NULL
                ORDER BY COALESCE(added, mtime) DESC LIMIT ?
                """) else { return out }
            defer { sqlite3_finalize(st) }
            bind(st, [.int(Int64(limit))])
            while sqlite3_step(st) == SQLITE_ROW {
                out.append((sqlite3_column_int64(st, 0), text(st, 1), text(st, 2),
                            SearchItemKind(rawValue: text(st, 3)) ?? .other, sqlite3_column_int64(st, 4)))
            }
            return out
        }
    }

    func pendingExtractionCount() -> Int {
        scalar("SELECT COUNT(*) FROM items WHERE extracted=0")
    }

    func totalCount() -> Int { scalar("SELECT COUNT(*) FROM items") }

    func countsBySource() -> [String: Int] {
        locked {
            var out: [String: Int] = [:]
            guard let st = prepare("SELECT source, COUNT(*) FROM items GROUP BY source") else { return out }
            defer { sqlite3_finalize(st) }
            while sqlite3_step(st) == SQLITE_ROW { out[text(st, 0)] = Int(sqlite3_column_int64(st, 1)) }
            return out
        }
    }

    private func scalar(_ sql: String) -> Int {
        locked {
            guard let st = prepare(sql) else { return 0 }
            defer { sqlite3_finalize(st) }
            return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int64(st, 0)) : 0
        }
    }

    func bodyText(id: Int64) -> String {
        locked {
            guard let st = prepare("SELECT body FROM items_fts WHERE rowid=?") else { return "" }
            defer { sqlite3_finalize(st) }
            bind(st, [.int(id)])
            return sqlite3_step(st) == SQLITE_ROW ? text(st, 0) : ""
        }
    }

    // MARK: - Learned aliases ("you searched X, then opened this" -> X now finds it)

    func learn(key: String, terms: [String]) {
        let clean = terms.map { $0.lowercased() }.filter { $0.count >= 3 }
        guard !clean.isEmpty else { return }
        locked {
            if let st = prepare("INSERT INTO learned(item_key,term,n) VALUES(?,?,1) ON CONFLICT(item_key,term) DO UPDATE SET n=n+1") {
                for t in clean {
                    sqlite3_reset(st)
                    bind(st, [.text(key), .text(t)])
                    sqlite3_step(st)
                }
                sqlite3_finalize(st)
            }
            var top: [String] = []
            if let st = prepare("SELECT term FROM learned WHERE item_key=? ORDER BY n DESC LIMIT 12") {
                bind(st, [.text(key)])
                while sqlite3_step(st) == SQLITE_ROW { top.append(text(st, 0)) }
                sqlite3_finalize(st)
            }
            if let st = prepare("UPDATE items_fts SET learned=? WHERE rowid=(SELECT id FROM items WHERE key=?)") {
                bind(st, [.text(top.joined(separator: " ")), .text(key)])
                sqlite3_step(st)
                sqlite3_finalize(st)
            }
        }
    }

    // MARK: - Searching

    private static func ftsQuote(_ s: String, prefix: Bool) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" + (prefix ? "*" : "")
    }

    private static func likeEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    func search(_ q: StoreQuery) -> [StoreHit] {
        locked {
            var ftsParts: [String] = []
            var likeClauses: [String] = []
            var likeBinds: [Bind] = []

            for group in q.termGroups where !group.isEmpty {
                let long = group.filter { $0.count >= 3 || !usesTrigram }
                if long.isEmpty {
                    // Trigram index cannot match <3 characters; fall back to LIKE on the short fields.
                    let pattern = "%" + IndexStore.likeEscape(group[0]) + "%"
                    likeClauses.append("(i.name LIKE ? ESCAPE '\\' OR i.sender LIKE ? ESCAPE '\\' OR i.origin LIKE ? ESCAPE '\\')")
                    likeBinds.append(contentsOf: [.text(pattern), .text(pattern), .text(pattern)])
                } else {
                    let alts = long.map { IndexStore.ftsQuote($0, prefix: !usesTrigram) }
                    ftsParts.append(alts.count == 1 ? alts[0] : "(" + alts.joined(separator: " OR ") + ")")
                }
            }
            let match: String? = ftsParts.isEmpty ? nil : ftsParts.joined(separator: q.matchAny ? " OR " : " AND ")

            let weights = "bm25(items_fts, 10.0, 4.0, 3.0, 1.0, 6.0)"
            let cols = "i.id,i.key,i.path,i.name,i.kind,i.source,i.ext,i.size,i.mtime,i.added,i.sender,i.origin,i.hidden,i.snippet,i.ref"
            var sql: String
            var binds: [Bind] = []
            if let match = match {
                sql = "SELECT \(cols), \(weights) FROM items_fts JOIN items i ON i.id = items_fts.rowid WHERE items_fts MATCH ?"
                binds.append(.text(match))
            } else {
                sql = "SELECT \(cols), 0.0 FROM items i WHERE 1=1"
            }

            for clause in likeClauses { sql += " AND " + clause }
            binds.append(contentsOf: likeBinds)

            if !q.includeHidden { sql += " AND i.hidden=0" }
            if !q.extensions.isEmpty {
                sql += " AND i.ext IN (" + q.extensions.map { _ in "?" }.joined(separator: ",") + ")"
                binds.append(contentsOf: q.extensions.map { .text($0) })
            }
            if !q.kinds.isEmpty {
                sql += " AND i.kind IN (" + q.kinds.map { _ in "?" }.joined(separator: ",") + ")"
                binds.append(contentsOf: q.kinds.map { .text($0.rawValue) })
            }
            if !q.sources.isEmpty {
                sql += " AND i.source IN (" + q.sources.map { _ in "?" }.joined(separator: ",") + ")"
                binds.append(contentsOf: q.sources.map { .text($0) })
            }
            if let p = q.pathContains {
                sql += " AND i.path LIKE ? ESCAPE '\\'"
                binds.append(.text("%" + IndexStore.likeEscape(p) + "%"))
            }
            if let range = q.dateRange {
                let a = range.start.timeIntervalSince1970, b = range.end.timeIntervalSince1970
                sql += " AND ((i.mtime BETWEEN ? AND ?) OR (i.added BETWEEN ? AND ?))"
                binds.append(contentsOf: [.real(a), .real(b), .real(a), .real(b)])
            }

            sql += match != nil ? " ORDER BY \(weights)" : " ORDER BY COALESCE(i.added, i.mtime) DESC"
            sql += " LIMIT ?"
            binds.append(.int(Int64(q.limit)))

            guard let st = prepare(sql) else { return [] }
            defer { sqlite3_finalize(st) }
            bind(st, binds)

            var hits: [StoreHit] = []
            while sqlite3_step(st) == SQLITE_ROW {
                hits.append(StoreHit(
                    id: sqlite3_column_int64(st, 0),
                    key: text(st, 1),
                    path: sqlite3_column_type(st, 2) == SQLITE_NULL ? nil : text(st, 2),
                    name: text(st, 3),
                    kind: SearchItemKind(rawValue: text(st, 4)) ?? .other,
                    source: text(st, 5),
                    ext: text(st, 6),
                    size: sqlite3_column_int64(st, 7),
                    mtime: Date(timeIntervalSince1970: sqlite3_column_double(st, 8)),
                    added: date(st, 9),
                    sender: text(st, 10),
                    origin: text(st, 11),
                    hidden: sqlite3_column_int(st, 12) != 0,
                    snippet: text(st, 13),
                    ref: text(st, 14),
                    bm25: sqlite3_column_double(st, 15)
                ))
            }
            return hits
        }
    }

    /// "Just arrived": newest things first, no query needed.
    func recent(limit: Int, includeHidden: Bool) -> [StoreHit] {
        var q = StoreQuery()
        q.limit = limit
        q.includeHidden = includeHidden
        q.kinds = SearchItemKind.allCases.filter { $0 != .folder && $0 != .application && $0 != .contact && $0 != .calendarEvent }
        return search(q)
    }
}
