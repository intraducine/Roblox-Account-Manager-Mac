import XCTest
@testable import RAMacApp

final class FeedbackViewTests: XCTestCase {
    private let metadata = FeedbackMetadata(
        appVersion: "1.2.3",
        build: "123",
        macOSVersion: "macOS 15.6.1",
        processor: "Apple silicon"
    )

    func testEmbedURLIncludesOnlySelectedMetadata() throws {
        let url = try XCTUnwrap(FeedbackConfiguration.embedURL(
            formID: "abc123",
            metadata: metadata,
            includesAppVersion: true,
            includesSystemInformation: false
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(url.host, "tally.so")
        XCTAssertEqual(url.path, "/embed/abc123")
        XCTAssertEqual(values["app_version"]!, "Version 1.2.3 (123)")
        XCTAssertFalse(values.keys.contains("system"))
        XCTAssertEqual(values["hideTitle"]!, "1")
        XCTAssertEqual(values["transparentBackground"]!, "1")
    }

    func testEmbedURLOmitsAllMetadataWhenUserClearsBothChoices() throws {
        let url = try XCTUnwrap(FeedbackConfiguration.embedURL(
            formID: "abc123",
            metadata: metadata,
            includesAppVersion: false,
            includesSystemInformation: false
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let names = Set((components.queryItems ?? []).map(\.name))

        XCTAssertFalse(names.contains("app_version"))
        XCTAssertFalse(names.contains("system"))
    }

    func testPlaceholderFormIDDoesNotProduceAURL() {
        XCTAssertNil(FeedbackConfiguration.embedURL(
            formID: "TALLY_FORM_ID",
            metadata: metadata,
            includesAppVersion: true,
            includesSystemInformation: true
        ))
    }

    func testNavigationAllowsOnlySecureTallyPages() {
        XCTAssertTrue(FeedbackBrowserModel.allowsMainFrameNavigation(
            to: URL(string: "https://tally.so/embed/6867A5")
        ))
        XCTAssertFalse(FeedbackBrowserModel.allowsMainFrameNavigation(
            to: URL(string: "http://tally.so/embed/6867A5")
        ))
        XCTAssertFalse(FeedbackBrowserModel.allowsMainFrameNavigation(
            to: URL(string: "https://tally.so.example.com/embed/6867A5")
        ))
        XCTAssertFalse(FeedbackBrowserModel.allowsMainFrameNavigation(
            to: URL(string: "https://tally.so/embed/another-form")
        ))
        XCTAssertFalse(FeedbackBrowserModel.allowsMainFrameNavigation(
            to: URL(string: "https://tally.so/")
        ))
    }
}
