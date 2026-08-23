import AppKit
import XCTest
@testable import RAMacApp

final class RemoteImageCacheTests: XCTestCase {
    @MainActor
    func testLoadedImageIsAvailableToAReplacementViewImmediately() throws {
        let url = try XCTUnwrap(URL(string: "https://tr.rbxcdn.com/\(UUID().uuidString).png"))
        let image = NSImage(size: NSSize(width: 32, height: 32))

        RemoteImageCache.insert(image, for: url)

        XCTAssertTrue(RemoteImageCache.image(for: url) === image)
    }
}
