import XCTest
@testable import RAMacCore

final class DiagnosticReportTests: XCTestCase {
    func testDefaultReportUsesTheCurrentDevelopmentVersion() {
        let report = DiagnosticReport(checks: [])

        XCTAssertEqual(report.appVersion, "1.1.2")
    }
}
