import Foundation
import RAMacCore

enum AppSmokeTestConfiguration {
    static let isEnabled = ProcessInfo.processInfo.environment["RAM_UI_SMOKE_TEST"] == "1"

    static let dataDirectory: URL = {
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
        if let rawPath = ProcessInfo.processInfo.environment["RAM_UI_SMOKE_DATA_DIRECTORY"],
           !rawPath.isEmpty {
            let candidate = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
            let allowedPrefixes = [
                temporaryDirectory.appendingPathComponent("ramac-ui-smoke.", isDirectory: true).path,
                "/tmp/ramac-ui-smoke.",
                "/private/tmp/ramac-ui-smoke."
            ]
            if allowedPrefixes.contains(where: candidate.path.hasPrefix) {
                return candidate
            }
        }
        return temporaryDirectory.appendingPathComponent(
            "ramac-ui-smoke.\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )
    }()

    static func reportMainWindowReady() {
        guard isEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            try Data("ready \(AppVersionInfo.currentVersion())\n".utf8).write(
                to: dataDirectory.appendingPathComponent("main-window-ready"),
                options: .atomic
            )
        } catch {
            fputs("UI smoke marker failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
