import Foundation
import QuickLookThumbnailing
import AppKit

public final class ThumbnailCacheService: @unchecked Sendable {
    public static let shared = ThumbnailCacheService()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    public func getCachedThumbnail(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }

    public func fetchThumbnail(
        for url: URL,
        size: CGSize = CGSize(width: 80, height: 80),
        completion: @escaping @MainActor @Sendable (NSImage?) -> Void
    ) {
        if let cached = cache.object(forKey: url as NSURL) {
            Task { @MainActor in
                completion(cached)
            }
            return
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] (rep, error) in
            guard let self = self, let rep = rep else {
                Task { @MainActor in
                    completion(nil)
                }
                return
            }

            let image = rep.nsImage
            self.cache.setObject(image, forKey: url as NSURL)
            Task { @MainActor in
                completion(image)
            }
        }
    }
}
