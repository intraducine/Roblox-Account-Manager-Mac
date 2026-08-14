import Foundation
import XCTest
@testable import RAMacApp

final class SoftwareUpdateMarkdownTests: XCTestCase {
    func testReleaseNotesMarkdownKeepsFormattingAndSecureLinks() throws {
        let rendered = ReleaseNotesMarkdown.parse(
            "## What's New\n\n- **Bulk opening** works.\n- [View details](https://github.com/example/release)"
        )

        XCTAssertTrue(String(rendered.characters).contains("What's New"))
        XCTAssertTrue(rendered.runs.contains {
            $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
        })
        XCTAssertEqual(
            rendered.runs.compactMap(\.link),
            [URL(string: "https://github.com/example/release")!]
        )
    }

    func testReleaseNotesMarkdownRemovesUnsafeLinks() {
        let rendered = ReleaseNotesMarkdown.parse(
            "[Unsafe](javascript:alert(1)) [Credentials](https://user:pass@example.com/)"
        )

        XCTAssertTrue(rendered.runs.compactMap(\.link).isEmpty)
        XCTAssertTrue(String(rendered.characters).contains("Unsafe"))
        XCTAssertTrue(String(rendered.characters).contains("Credentials"))
    }

    func testReleaseNotesMarkdownPreservesBlockStructure() {
        let blocks = ReleaseNotesMarkdown.blocks(in: """
        ## What changed

        - First item
        - Second **item**

        A final paragraph.
        """)

        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "What changed"),
            .unorderedList(["First item", "Second **item**"]),
            .paragraph("A final paragraph.")
        ])
    }
}
