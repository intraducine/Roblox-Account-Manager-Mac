import XCTest
@testable import RAMacApp

final class AppGeometryTests: XCTestCase {
    func testWindowEdgeInsetKeepsControlAndWindowCornersConcentric() {
        XCTAssertEqual(
            AppGeometry.windowEdgeControlInset + AppGeometry.controlCornerRadius,
            AppGeometry.windowCornerRadius
        )
    }

    func testPanelInsetKeepsControlAndPanelCornersConcentric() {
        XCTAssertEqual(
            AppGeometry.panelEdgeControlInset + AppGeometry.controlCornerRadius,
            AppGeometry.panelCornerRadius
        )
    }
}
