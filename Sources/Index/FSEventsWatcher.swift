import Foundation
import CoreServices

/// Keeps the index current: every new/changed/deleted file reaches the index within a couple of seconds.
final class FSEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "dadsearch.fsevents", qos: .utility)
    private let paths: [String]
    private let exclusions: [String]
    private let handler: @Sendable ([String]) -> Void
    private var pending = Set<String>()
    private var flushItem: DispatchWorkItem?

    init(paths: [String], exclusions: [String] = [], handler: @escaping @Sendable ([String]) -> Void) {
        self.paths = paths
        self.exclusions = exclusions
        self.handler = handler
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(eventPaths, to: CFArray.self) as NSArray
            watcher.receive((array as? [String]) ?? [])
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.5, flags
        ) else { return }
        if !exclusions.isEmpty { _ = FSEventStreamSetExclusionPaths(created, exclusions as CFArray) }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    /// Called on `queue`. Coalesce bursts (a download writes many events) into one flush.
    fileprivate func receive(_ events: [String]) {
        pending.formUnion(events)
        flushItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let batch = Array(self.pending)
            self.pending.removeAll()
            if !batch.isEmpty { self.handler(batch) }
        }
        flushItem = item
        queue.asyncAfter(deadline: .now() + 1.0, execute: item)
    }
}
