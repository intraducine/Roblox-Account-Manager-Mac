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
        Routine updates now need fewer macOS approvals.

        ## What changed

        - Skip repeated Keychain access migration.
        - Check Accessibility access before arranging windows.

        ## Before you update

        - No extra steps are required.

        ## Verification

        - `swift test --parallel` passes.
        """)

        XCTAssertEqual(blocks, [
            .paragraph("Routine updates now need fewer macOS approvals."),
            .heading(level: 2, text: "What changed"),
            .unorderedList([
                "Skip repeated Keychain access migration.",
                "Check Accessibility access before arranging windows."
            ]),
            .heading(level: 2, text: "Before you update"),
            .unorderedList(["No extra steps are required."]),
            .heading(level: 2, text: "Verification"),
            .unorderedList(["`swift test --parallel` passes."])
        ])
    }
}
