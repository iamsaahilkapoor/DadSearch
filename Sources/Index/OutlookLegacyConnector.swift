import Foundation
import SQLite3
import AppKit

struct OutlookSyncReport: Sendable {
    var installed = false
    var profileFound = false
    var databaseReadable = false
    var messagesIndexed = 0
    var table = ""
    var note = ""
}

/// Indexes mail from *Legacy* Outlook for Mac (Outlook 16.x with the "New Outlook" switch OFF).
///
/// Legacy Outlook keeps its mailbox in `Outlook 15 Profiles/<profile>/Data/Outlook.sqlite` and Microsoft's own
/// Spotlight importer indexes the message bodies. We therefore combine two sources:
///   1. Outlook.sqlite (read-only)  -> subject / sender / date / preview for EVERY message, in our own index
///   2. Spotlight (SpotlightSearchEngine) -> full message-body search, merged at query time
/// The table and column names are discovered at run time (PRAGMA table_info), so a different Outlook build
/// does not silently break indexing; the Health panel reports exactly what was found.
final class OutlookLegacyConnector: @unchecked Sendable {
    static let shared = OutlookLegacyConnector()

    private let store = IndexStore.shared
    private let queue = DispatchQueue(label: "dadsearch.outlook", qos: .utility)
    private var debounce: DispatchWorkItem?
    private var lastSync = Date.distantPast
    private(set) var lastReport = OutlookSyncReport()

    static var outlookAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.Outlook")
    }

    static var profilesRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles")
    }

    static var watchedDirectory: String {
        NSHomeDirectory() + "/Library/Group Containers/UBF8T346G9.Office/Outlook"
    }

    /// Call whenever FSEvents reports activity inside Outlook's folder.
    func scheduleSync(after delay: TimeInterval = 20) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.debounce?.cancel()
            let item = DispatchWorkItem { [weak self] in _ = self?.sync() }
            self.debounce = item
            self.queue.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    @discardableResult
    func sync() -> OutlookSyncReport {
        var report = OutlookSyncReport()
        report.installed = OutlookLegacyConnector.outlookAppURL != nil

        let fm = FileManager.default
        guard let profiles = try? fm.contentsOfDirectory(atPath: OutlookLegacyConnector.profilesRoot.path) else {
            report.note = report.installed
                ? "Outlook is installed but its data folder can't be read. Full Disk Access is probably missing."
                : "Outlook not found."
            lastReport = report
            return report
        }

        var keep = Set<String>()
        for profile in profiles where !profile.hasPrefix(".") {
            let dataDir = OutlookLegacyConnector.profilesRoot.appendingPathComponent(profile).appendingPathComponent("Data")
            let dbURL = dataDir.appendingPathComponent("Outlook.sqlite")
            guard fm.fileExists(atPath: dbURL.path) else { continue }
            report.profileFound = true

            // Attachments Outlook stored on disk: plain files, so the normal crawler (with OCR/text extraction) can index them.
            let attachments = dataDir.appendingPathComponent("Message Attachments")
            if fm.fileExists(atPath: attachments.path) {
                let known = store.signatures(sources: ["outlook-attachment"])
                IndexCrawler.shared.crawl(root: attachments, known: known, sourceOverride: "outlook-attachment")
            }

            let (n, table, readable) = indexMessages(dbURL: dbURL, dataDir: dataDir, profile: profile, keep: &keep)
            report.databaseReadable = report.databaseReadable || readable
            report.messagesIndexed += n
            if !table.isEmpty { report.table = table }
        }

        if report.databaseReadable {
            store.deleteMissing(source: "outlook", keep: keep)
        }
        if !report.profileFound { report.note = "No Outlook profile with a mail database was found." }
        else if !report.databaseReadable { report.note = "Outlook's database could not be opened (it may be locked or damaged)." }
        else if report.messagesIndexed == 0 { report.note = "Outlook database opened, but no message table was recognised." }

        lastSync = Date()
        lastReport = report
        ExtractionWorker.shared.kick()
        return report
    }

    // MARK: - Reading Outlook.sqlite

    private func indexMessages(dbURL: URL, dataDir: URL, profile: String, keep: inout Set<String>) -> (Int, String, Bool) {
        var tempDir: URL? = nil
        var handle: OpaquePointer? = nil
        if sqlite3_open_v2(dbURL.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(handle)
            handle = nil
            // Locked or mid-write: work on a private copy (database + write-ahead log).
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("DadSearch-outlook-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: dbURL.path + suffix)
                if FileManager.default.fileExists(atPath: src.path) {
                    try? FileManager.default.copyItem(at: src, to: tmp.appendingPathComponent("Outlook.sqlite" + suffix))
                }
            }
            tempDir = tmp
            if sqlite3_open_v2(tmp.appendingPathComponent("Outlook.sqlite").path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
                sqlite3_close(handle)
                try? FileManager.default.removeItem(at: tmp)
                return (0, "", false)
            }
        }
        defer {
            sqlite3_close(handle)
            if let t = tempDir { try? FileManager.default.removeItem(at: t) }
        }
        sqlite3_busy_timeout(handle, 3000)

        guard let layout = discoverMessageTable(handle) else { return (0, "", true) }

        let select = layout.selectList.joined(separator: ", ")
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT \(select) FROM \"\(layout.table)\"", -1, &st, nil) == SQLITE_OK else {
            return (0, layout.table, true)
        }
        defer { sqlite3_finalize(st) }

        var batch: [IndexRecord] = []
        var count = 0
        while sqlite3_step(st) == SQLITE_ROW {
            func str(_ key: String) -> String {
                guard let i = layout.position[key] else { return "" }
                switch sqlite3_column_type(st, Int32(i)) {
                case SQLITE_TEXT:
                    return sqlite3_column_text(st, Int32(i)).map { String(cString: $0) } ?? ""
                case SQLITE_INTEGER:
                    return String(sqlite3_column_int64(st, Int32(i)))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(st, Int32(i)))
                    guard n > 0, let p = sqlite3_column_blob(st, Int32(i)) else { return "" }
                    return String(decoding: Data(bytes: p, count: min(n, 4000)), as: UTF8.self)
                default: return ""
                }
            }
            func num(_ key: String) -> Double? {
                guard let i = layout.position[key], sqlite3_column_type(st, Int32(i)) != SQLITE_NULL else { return nil }
                return sqlite3_column_double(st, Int32(i))
            }

            let rowID = str("id")
            guard !rowID.isEmpty else { continue }
            var subject = str("subject").trimmingCharacters(in: .whitespacesAndNewlines)
            if subject.isEmpty { subject = "(no subject)" }
            let sender = str("sender")
            let to = str("to")
            let preview = str("preview").trimmingCharacters(in: .whitespacesAndNewlines)
            let received = OutlookLegacyConnector.date(from: num("time")) ?? Date.distantPast
            var path: String? = nil
            let rel = str("path")
            if !rel.isEmpty {
                let candidate = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : dataDir.appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: candidate.path) { path = candidate.path }
            }

            let key = "outlook:\(profile):\(rowID)"
            keep.insert(key)
            batch.append(IndexRecord(
                key: key,
                path: path,
                name: subject,
                kind: .email,
                source: "outlook",
                ext: "",
                size: 0,
                mtime: received,
                added: received,
                sender: sender,
                origin: "Outlook " + to,
                hidden: false,
                snippet: String(preview.prefix(300)),
                ref: rowID,
                body: preview,
                needsExtraction: false
            ))
            count += 1
            if batch.count >= 1000 {
                store.upsert(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty { store.upsert(batch) }
        return (count, layout.table, true)
    }

    private struct TableLayout {
        var table: String
        var selectList: [String]
        var position: [String: Int]
    }

    /// Finds the message table by looking for subject + sender columns, then maps columns by name patterns.
    private func discoverMessageTable(_ handle: OpaquePointer?) -> TableLayout? {
        func rows(_ sql: String, col: Int32 = 0) -> [String] {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &st, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(st) }
            var out: [String] = []
            while sqlite3_step(st) == SQLITE_ROW {
                if let c = sqlite3_column_text(st, col) { out.append(String(cString: c)) }
            }
            return out
        }
        func firstMatch(_ cols: [String], exact: [String], pattern: String) -> String? {
            for e in exact { if let c = cols.first(where: { $0.caseInsensitiveCompare(e) == .orderedSame }) { return c } }
            return cols.first { $0.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        }

        var best: (layout: TableLayout, rowCount: Int)? = nil
        for table in rows("SELECT name FROM sqlite_master WHERE type='table'") {
            let cols = rows("PRAGMA table_info(\"\(table)\")", col: 1)
            guard let subject = firstMatch(cols, exact: ["Message_NormalizedSubject", "Message_Subject"], pattern: "subject"),
                  let sender = firstMatch(cols, exact: ["Message_SenderList", "Message_SenderAddressList"], pattern: "sender")
            else { continue }

            let idCol = firstMatch(cols, exact: ["Record_RecordID"], pattern: "recordid") ?? "rowid"
            var picks: [(String, String)] = [("id", idCol), ("subject", subject), ("sender", sender)]
            if let c = firstMatch(cols, exact: ["Message_ToRecipientAddressList"], pattern: "recipient|toaddress") { picks.append(("to", c)) }
            if let c = firstMatch(cols, exact: ["Message_TimeReceived"], pattern: "timereceived|received") { picks.append(("time", c)) }
            if let c = firstMatch(cols, exact: ["Message_Preview"], pattern: "preview") { picks.append(("preview", c)) }
            if let c = firstMatch(cols, exact: ["PathToDataFile"], pattern: "pathtodatafile|datafile") { picks.append(("path", c)) }

            let count = Int(rows("SELECT COUNT(*) FROM \"\(table)\"").first ?? "0") ?? 0
            var position: [String: Int] = [:]
            var list: [String] = []
            for (i, p) in picks.enumerated() {
                position[p.0] = i
                list.append("\"\(p.1)\"")
            }
            let layout = TableLayout(table: table, selectList: list, position: position)
            if best == nil || count > best!.rowCount { best = (layout, count) }
        }
        return best?.layout
    }

    /// Outlook stores times as Unix seconds, Unix milliseconds or Core-Data (2001-epoch) seconds depending on version.
    static func date(from value: Double?) -> Date? {
        guard let v = value, v > 0 else { return nil }
        if v > 1e11 { return Date(timeIntervalSince1970: v / 1000) }
        if v > 1.2e9 { return Date(timeIntervalSince1970: v) }
        if v > 1e8 { return Date(timeIntervalSinceReferenceDate: v) }
        return Date(timeIntervalSince1970: v)
    }

    // MARK: - Opening a message

    /// Opens the exact message in Outlook (needs the Automation permission the first time).
    @MainActor
    static func openMessage(recordID: String) -> Bool {
        guard let id = Int(recordID) else { return false }
        let source = """
        tell application "Microsoft Outlook"
            activate
            open (message id \(id))
        end tell
        """
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&error)
        return error == nil
    }

    /// Re-runs Microsoft's own Spotlight importer on the profile folder (fixes "Outlook search finds nothing").
    func repairSpotlightIndex() {
        guard let app = OutlookLegacyConnector.outlookAppURL else { return }
        let importer = app.appendingPathComponent("Contents/Library/Spotlight/Microsoft Outlook Spotlight Importer.mdimporter").path
        queue.async {
            _ = ContentExtractor.runTool("/usr/bin/mdimport", ["-g", importer, "-d1", OutlookLegacyConnector.profilesRoot.path], timeout: 600)
        }
    }
}
