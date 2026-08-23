import AppKit
import XCTest
@testable import RAMacApp

final class ApplicationLifecycleDelegateTests: XCTestCase {
    func testAppTerminatesAfterItsLastWindowCloses() {
        let delegate = ApplicationLifecycleDelegate()

        XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
