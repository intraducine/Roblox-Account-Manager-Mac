import XCTest
@testable import RAMacCore

final class WindowArrangementTests: XCTestCase {
    func testSavedPolicyShowsCurrentSavedPlacements() {
        let includedID = UUID()
        let excludedID = UUID()
        let included = assignment(accountID: includedID, region: .left)
        let excluded = assignment(accountID: excludedID, region: .right)

        let resolved = WindowArrangementPolicy.savedPlacements.effectiveAssignments(
            savedAssignments: [excluded, included],
            accountIDs: [includedID]
        )

        XCTAssertEqual(resolved, [included])
        XCTAssertTrue(WindowArrangementPolicy.savedPlacements.usesSavedPlacements)
    }

    func testCustomPolicyShowsItsOverrideInsteadOfSavedPlacements() {
        let accountID = UUID()
        let saved = assignment(accountID: accountID, region: .left)
        let custom = assignment(accountID: accountID, region: .topRight)
        let policy = WindowArrangementPolicy.custom([custom])

        let resolved = policy.effectiveAssignments(
            savedAssignments: [saved],
            accountIDs: [accountID]
        )

        XCTAssertEqual(resolved, [custom])
        XCTAssertFalse(policy.usesSavedPlacements)
    }

    func testLegacyUnchangedPolicyAppearsAsAnEmptyOverride() {
        let accountID = UUID()
        let saved = assignment(accountID: accountID, region: .wholeScreen)
        let policy = WindowArrangementPolicy.unchanged

        XCTAssertEqual(
            policy.effectiveAssignments(savedAssignments: [saved], accountIDs: [accountID]),
            []
        )
        XCTAssertFalse(policy.usesSavedPlacements)
    }

    func testNativeFullScreenPlacementRoundTripsThroughSavedLaunchSetData() throws {
        let original = assignment(accountID: UUID(), region: .fullScreen)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WindowLayoutAssignment.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.region, .fullScreen)
    }

    private func assignment(
        accountID: UUID,
        region: WindowPlacementRegion
    ) -> WindowLayoutAssignment {
        WindowLayoutAssignment(
            accountID: accountID,
            displayID: "main",
            displayName: "Main Display",
            displayPixelWidth: 2560,
            displayPixelHeight: 1440,
            region: region
        )
    }
}
