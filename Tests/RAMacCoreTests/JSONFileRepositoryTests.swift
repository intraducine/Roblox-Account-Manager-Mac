import Foundation
import XCTest
@testable import RAMacCore

final class JSONFileRepositoryTests: XCTestCase {
    private struct Record: Codable, Equatable, Sendable {
        let value: String
    }

    func testSecondSaveKeepsThePreviousValidGenerationAsBackup() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        try fixture.repository.save([Record(value: "first")])
        try fixture.repository.save([Record(value: "second")])

        XCTAssertEqual(try fixture.repository.load(), [Record(value: "second")])
        XCTAssertEqual(
            try JSONDecoder().decode([Record].self, from: Data(contentsOf: fixture.backupURL)),
            [Record(value: "first")]
        )
    }

    func testDamagedCurrentFileRecoversAndRestoresTheLastValidBackup() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        try fixture.repository.save([Record(value: "first")])
        try fixture.repository.save([Record(value: "second")])
        try Data("not json".utf8).write(to: fixture.fileURL)

        let result = try fixture.repository.loadWithRecovery()

        XCTAssertTrue(result.recoveredFromBackup)
        XCTAssertEqual(result.records, [Record(value: "first")])
        XCTAssertEqual(try fixture.repository.load(), [Record(value: "first")])
    }

    func testDamagedFileWithoutBackupIsKeptAndReported() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let damagedData = Data("not json".utf8)
        try damagedData.write(to: fixture.fileURL)

        XCTAssertThrowsError(try fixture.repository.loadWithRecovery()) { error in
            XCTAssertTrue(error.localizedDescription.contains("Records.json is damaged"))
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), damagedData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.backupURL.path))
    }

    func testSavingOverDamagedCurrentFileDoesNotReplaceAValidBackup() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        try fixture.repository.save([Record(value: "first")])
        try fixture.repository.save([Record(value: "second")])
        let backupData = try Data(contentsOf: fixture.backupURL)
        try Data("not json".utf8).write(to: fixture.fileURL)

        try fixture.repository.save([Record(value: "third")])

        XCTAssertEqual(try Data(contentsOf: fixture.backupURL), backupData)
        XCTAssertEqual(try fixture.repository.load(), [Record(value: "third")])
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ram-json-repository-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Fixture(
            directory: directory,
            repository: JSONFileRepository<Record>(fileName: "Records.json", dataDirectory: directory)
        )
    }

    private struct Fixture {
        let directory: URL
        let repository: JSONFileRepository<Record>

        var fileURL: URL { directory.appendingPathComponent("Records.json") }
        var backupURL: URL { directory.appendingPathComponent("Records.backup.json") }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
