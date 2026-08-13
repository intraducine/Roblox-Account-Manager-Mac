import AppKit

enum RemoteImageCache {
    private static let images = NSCache<NSURL, NSImage>()

    static func image(for url: URL?) -> NSImage? {
        url.flatMap { images.object(forKey: $0 as NSURL) }
    }

    static func insert(_ image: NSImage, for url: URL) {
        images.setObject(image, forKey: url as NSURL)
    }
}
