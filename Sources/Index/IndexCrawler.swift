import Foundation

struct CrawlStatus: Sendable {
    var running = false
    var itemsSeen = 0
    var lastFinished: Date? = nil
    /// Folders macOS refused to let us read (needs Full Disk Access).
    var blockedPaths: [String] = []
}

enum CrawlRules {
    /// Folders that are never worth indexing (millions of machine-generated files).
    static let skipDirectoryNames: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", "__pycache__", ".venv", "venv", "site-packages",
        "Pods", ".gradle", ".cargo", ".rustup", ".npm", ".cache", ".docker", ".Spotlight-V100", ".fseventsd",
        ".DocumentRevisions-V100", ".TemporaryItems", ".MobileBackups", "CachedData", ".Trashes"
    ]

    static var home: String { NSHomeDirectory() }
    static var library: String { home + "/Library" }

    static func shouldSkipDirectory(name: String, path: String) -> Bool {
        if path == library { return true }          // handled through an explicit allow-list instead
        return skipDirectoryNames.contains(name)
    }

    /// Paths under ~/Library we DO index (user content that happens to live there).
    static func libraryAllowlist() -> [URL] {
        let fm = FileManager.default
        let lib = URL(fileURLWithPath: library)
        var roots: [URL] = []
        for rel in ["Mobile Documents", "Messages/Attachments", "Mail Downloads",
                    "Containers/com.apple.mail/Data/Library/Mail Downloads"] {
            let u = lib.appendingPathComponent(rel)
            if fm.fileExists(atPath: u.path) { roots.append(u) }
        }
        // WhatsApp / Telegram containers: discovered by name so we don't depend on a hard-coded bundle id.
        for container in ["Group Containers", "Containers"] {
            let dir = lib.appendingPathComponent(container)
            if let names = try? fm.contentsOfDirectory(atPath: dir.path) {
                for n in names {
                    let l = n.lowercased()
                    if l.contains("whatsapp") || l.contains("telegram") || l.contains("keepcoder") {
                        roots.append(dir.appendingPathComponent(n))
                    }
                }
            }
        }
        return roots
    }

    /// True when a path from a file-system event should be ignored.
    static func isIgnoredEventPath(_ path: String) -> Bool {
        if path.hasPrefix(library) {
            return !libraryAllowlist().contains { path.hasPrefix($0.path) }
        }
        for comp in skipDirectoryNames where path.contains("/\(comp)/") { return true }
        if path.contains("/Application Support/DadSearch/") { return true }
        return false
    }
}

/// Walks the disk (including hidden files and folders) and writes what it finds into the IndexStore.
/// After the first run it only touches files whose modification time or size changed.
final class IndexCrawler: @unchecked Sendable {
    static let shared = IndexCrawler()

    private let store = IndexStore.shared
    private let queue = DispatchQueue(label: "dadsearch.crawler", qos: .utility)
    private let stateLock = NSLock()
    private var _status = CrawlStatus()
    private let fileSources = ["file", "messages", "whatsapp", "telegram", "mail-attachment"]

    var onStatusChange: (@Sendable (CrawlStatus) -> Void)?

    var status: CrawlStatus {
        stateLock.lock(); defer { stateLock.unlock() }
        return _status
    }

    private func update(_ change: (inout CrawlStatus) -> Void) {
        stateLock.lock()
        change(&_status)
        let snapshot = _status
        stateLock.unlock()
        onStatusChange?(snapshot)
    }

    // MARK: - Full crawl

    func startFullCrawl(force: Bool = false) {
        if status.running { return }
        if !force, let last = store.getMeta("last_full_crawl").flatMap(Double.init),
           Date().timeIntervalSince1970 - last < 6 * 3600 {
            // Recent enough: FSEvents keeps us current. Still make sure content extraction continues.
            ExtractionWorker.shared.kick()
            return
        }
        update { $0.running = true; $0.itemsSeen = 0; $0.blockedPaths = [] }
        queue.async { [weak self] in
            guard let self = self else { return }
            let known = self.store.signatures(sources: self.fileSources)
            var roots: [URL] = [URL(fileURLWithPath: CrawlRules.home)]
            roots.append(contentsOf: CrawlRules.libraryAllowlist())
            roots.append(contentsOf: self.externalVolumes())
            for root in roots {
                self.crawl(root: root, known: known, sourceOverride: nil)
            }
            self.store.purgeMissing(sources: self.fileSources)
            self.store.setMeta("last_full_crawl", String(Date().timeIntervalSince1970))
            self.update { $0.running = false; $0.lastFinished = Date() }
            ExtractionWorker.shared.kick()
        }
    }

    private func externalVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsRootFileSystemKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return vols.filter { (try? $0.resourceValues(forKeys: Set(keys)).volumeIsRootFileSystem) != true && $0.path != "/" && !$0.path.hasPrefix("/System") }
    }

    // MARK: - Crawl one root

    /// Walks `root`. Used by the full crawl, by new-folder events and by connectors (Outlook attachments).
    func crawl(root: URL, known: [String: (Double, Int64)], sourceOverride: String?) {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
            .contentModificationDateKey, .addedToDirectoryDateKey, .creationDateKey, .fileSizeKey
        ]
        var blocked: [String] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],          // NOTE: no .skipsHiddenFiles — hidden files are searchable
            errorHandler: { url, error in
                let ns = error as NSError
                if ns.code == NSFileReadNoPermissionError || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(EPERM)) {
                    blocked.append(url.path)
                }
                return true
            }
        ) else { return }

        var batch: [IndexRecord] = []
        var seen = 0
        let home = CrawlRules.home
        let deepOriginRoots = [home + "/Downloads", home + "/Desktop", home + "/Documents"]

        for case let url as URL in enumerator {
            let path = url.path
            let name = url.lastPathComponent
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            let isDir = v.isDirectory ?? false
            let isPackage = v.isPackage ?? false

            if isDir && !isPackage && CrawlRules.shouldSkipDirectory(name: name, path: path) {
                enumerator.skipDescendants()
                continue
            }

            seen += 1
            let mtime = v.contentModificationDate ?? Date()
            let size = Int64(v.fileSize ?? 0)
            if let sig = known[path], sig.0 == mtime.timeIntervalSince1970, sig.1 == size { continue }

            let ext = url.pathExtension.lowercased()
            let source = sourceOverride ?? KindClassifier.source(forPath: path)
            let kind = KindClassifier.kind(ext: ext, name: name, isDirectory: isDir, isPackage: isPackage, path: path)

            var origin = ""
            if !isDir, source != "file" || deepOriginRoots.contains(where: { path.hasPrefix($0) }) {
                origin = XAttr.originText(for: path)
            }
            if source == "messages" { origin = "iMessage " + origin }
            if source == "whatsapp" { origin = "WhatsApp " + origin }
            if source == "telegram" { origin = "Telegram " + origin }

            batch.append(IndexRecord(
                key: path,
                path: path,
                name: name,
                kind: kind,
                source: source,
                ext: ext,
                size: size,
                mtime: mtime,
                added: v.addedToDirectoryDate ?? v.creationDate,
                origin: origin,
                hidden: (v.isHidden ?? false) || name.hasPrefix(".") || path.contains("/."),
                needsExtraction: !isDir && ContentExtractor.canExtract(ext: ext, size: size)
            ))

            if batch.count >= 800 {
                store.upsert(batch)
                batch.removeAll(keepingCapacity: true)
            }
            if seen % 2000 == 0 { update { $0.itemsSeen += 2000 } }
        }
        if !batch.isEmpty { store.upsert(batch) }
        if !blocked.isEmpty { update { $0.blockedPaths.append(contentsOf: blocked) } }
    }

    // MARK: - Incremental (driven by FSEvents)

    func refresh(paths: [String]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var needsExtraction = false
            for path in paths where !CrawlRules.isIgnoredEventPath(path) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                    let url = URL(fileURLWithPath: path)
                    if isDir.boolValue {
                        // New or changed folder: index the folder and (re)walk its contents.
                        let known = self.store.signatures(sources: self.fileSources, pathPrefix: path + "/")
                        self.crawlSingle(url)
                        self.crawl(root: url, known: known, sourceOverride: nil)
                    } else {
                        self.crawlSingle(url)
                    }
                    needsExtraction = true
                } else {
                    self.store.deleteByPath(path)
                    self.store.deleteByPrefix(path + "/")
                }
            }
            if needsExtraction { ExtractionWorker.shared.kick() }
        }
    }

    private func crawlSingle(_ url: URL) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .isHiddenKey, .contentModificationDateKey,
            .addedToDirectoryDateKey, .creationDateKey, .fileSizeKey
        ]
        guard let v = try? url.resourceValues(forKeys: keys) else { return }
        let path = url.path
        let name = url.lastPathComponent
        let isDir = v.isDirectory ?? false
        let isPackage = v.isPackage ?? false
        let ext = url.pathExtension.lowercased()
        let source = KindClassifier.source(forPath: path)
        let size = Int64(v.fileSize ?? 0)
        let origin = isDir ? "" : XAttr.originText(for: path)
        store.upsert([IndexRecord(
            key: path, path: path, name: name,
            kind: KindClassifier.kind(ext: ext, name: name, isDirectory: isDir, isPackage: isPackage, path: path),
            source: source, ext: ext, size: size,
            mtime: v.contentModificationDate ?? Date(),
            added: v.addedToDirectoryDate ?? v.creationDate,
            origin: origin,
            hidden: (v.isHidden ?? false) || name.hasPrefix(".") || path.contains("/."),
            needsExtraction: !isDir && ContentExtractor.canExtract(ext: ext, size: size)
        )])
    }
}
