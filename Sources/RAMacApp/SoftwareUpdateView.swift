import AppKit
import RAMacCore
import SwiftUI

@MainActor
final class SoftwareUpdateController: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate(String)
        case available(SoftwareUpdateRelease)
        case downloading(SoftwareUpdateRelease)
        case ready(PreparedSoftwareUpdate)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let currentVersion: String
    private let service: GitHubSoftwareUpdateService
    private let installer: SoftwareUpdateInstaller
    private let applicationURL: URL

    init(
        service: GitHubSoftwareUpdateService = GitHubSoftwareUpdateService(),
        applicationURL: URL = Bundle.main.bundleURL,
        currentVersion: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.service = service
        installer = SoftwareUpdateInstaller(service: service, fileManager: fileManager)
        self.applicationURL = applicationURL
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "Development build"
    }

    func check() {
        discardPreparedUpdate()
        state = .checking
        Task {
            do {
                switch try await service.check(currentVersion: currentVersion) {
                case .upToDate(let version): state = .upToDate(version)
                case .available(let release): state = .available(release)
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func download(_ release: SoftwareUpdateRelease) {
        state = .downloading(release)
        Task {
            do {
                state = .ready(try await service.downloadAndPrepare(
                    release,
                    currentApplicationURL: applicationURL
                ))
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func installAndRestart(_ prepared: PreparedSoftwareUpdate) {
        state = .installing
        var backupURL: URL?
        do {
            backupURL = try installer.install(prepared, replacing: applicationURL)
            service.discard(prepared)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", applicationURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw SoftwareUpdateError.installationFailed
            }
            NSApplication.shared.terminate(nil)
        } catch {
            if let backupURL {
                try? installer.restorePreviousVersion(from: backupURL, to: applicationURL)
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func discardPreparedUpdate() {
        if case .ready(let prepared) = state { service.discard(prepared) }
    }
}

struct SoftwareUpdateView: View {
    @ObservedObject var controller: SoftwareUpdateController

    var body: some View {
        Form {
            Section("Installed Version") {
                LabeledContent("Version", value: controller.currentVersion)
            }

            Section("Update Status") {
                statusContent
            }

            Section("How Updates Stay Safe") {
                Text("The app downloads releases only from this project's public GitHub page. It checks the published file fingerprint and confirms that the new app has the same signing identity before it installs anything.")
                    .foregroundStyle(.secondary)
                Text("The previous app version stays in a hidden backup beside the installed app. A failed replacement restores it automatically.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Software Update")
        .frame(width: 620, height: 480)
        .onAppear {
            if case .idle = controller.state { controller.check() }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch controller.state {
        case .idle:
            Button("Check for Updates") { controller.check() }
                .buttonStyle(.borderedProminent)
        case .checking:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking GitHub for a newer release")
            }
        case .upToDate(let version):
            Label("No newer final release was found. You have version \(version).", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button("Check Again") { controller.check() }
        case .available(let release):
            Label("Version \(release.version.description) is available.", systemImage: "arrow.down.circle.fill")
                .fontWeight(.semibold)
            if !release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DisclosureGroup("What Changed") {
                    ScrollView {
                        Text(release.notes)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
            }
            HStack {
                Button("Download Update") { controller.download(release) }
                    .buttonStyle(.borderedProminent)
                Link("View Release on GitHub", destination: release.pageURL)
            }
        case .downloading(let release):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Downloading and checking version \(release.version.description)")
            }
        case .ready(let prepared):
            Label("Version \(prepared.release.version.description) is ready to install.", systemImage: "checkmark.seal.fill")
                .fontWeight(.semibold)
            Text("The app will restart. Your accounts, groups, notes, games, and saved sign-ins will stay in place.")
                .foregroundStyle(.secondary)
            Button("Install and Restart") { controller.installAndRestart(prepared) }
                .buttonStyle(.borderedProminent)
        case .installing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Installing the update and restarting")
            }
        case .failed(let message):
            Label("Update Failed", systemImage: "exclamationmark.triangle.fill")
                .fontWeight(.semibold)
            Text(message).foregroundStyle(.secondary)
            HStack {
                Button("Try Again") { controller.check() }
                    .buttonStyle(.borderedProminent)
                Link(
                    "Open GitHub Releases",
                    destination: URL(string: "https://github.com/\(GitHubSoftwareUpdateService.repository)/releases")!
                )
            }
        }
    }
}
