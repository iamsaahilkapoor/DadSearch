import Foundation
import CoreServices

public final class FSEventsService: @unchecked Sendable {
    public static let shared = FSEventsService()

    private var eventStream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.saahil.DadSearch.fseventsQueue", qos: .utility)
    private var isStarted = false

    private init() {}

    public func start() {
        guard !isStarted else { return }

        let home = NSHomeDirectory()
        let pathsToWatch: [String] = [
            home + "/Downloads",
            home + "/Desktop",
            home + "/Pictures/Screenshots",
            home + "/Pictures",
            home + "/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Identity/Files",
            home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        ].filter { FileManager.default.fileExists(atPath: $0) }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<FSEventsService>.fromOpaque(clientInfo).takeUnretainedValue()

            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            watcher.handleEvents(paths: paths)
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            flags
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            isStarted = true
            print("DadSearch: FSEvents watcher started on \(pathsToWatch.count) directories.")
        }
    }

    public func stop() {
        guard isStarted, let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        isStarted = false
    }

    private func handleEvents(paths: [String]) {
        for path in paths {
            let url = URL(fileURLWithPath: path)
            // Skip hidden files, system temporary partial downloads
            if url.lastPathComponent.hasPrefix(".") || url.pathExtension == "crdownload" || url.pathExtension == "download" {
                continue
            }

            guard FileManager.default.fileExists(atPath: path) else { continue }

            // Ingest file into ArrivalRadar and local FTS5 database
            Task.detached(priority: .utility) {
                await DocumentContentExtractor.shared.indexFile(at: url)
            }
        }
    }
}
