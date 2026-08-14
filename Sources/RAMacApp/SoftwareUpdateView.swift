import AppKit
import RAMacCore
import SwiftUI

enum ReleaseNotesMarkdown {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case quote(String)
        case code(String)
        case divider
    }

    static func parse(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return sanitize((try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source))
    }

    static func parseInline(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return sanitize((try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source))
    }

    static func blocks(in source: String) -> [Block] {
        let lines = source.components(separatedBy: .newlines)
        var result: [Block] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                index += 1
                var codeLines: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.code(codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(from: trimmed) {
                result.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if isDivider(trimmed) {
                result.append(.divider)
                index += 1
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                var items = [item]
                index += 1
                while index < lines.count,
                      let next = unorderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                result.append(.unorderedList(items))
                continue
            }

            if let item = orderedItem(from: trimmed) {
                var items = [item]
                index += 1
                while index < lines.count,
                      let next = orderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(next)
                    index += 1
                }
                result.append(.orderedList(items))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                result.append(.quote(quoteLines.joined(separator: " ")))
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                guard !candidate.isEmpty, !startsBlock(candidate) else { break }
                paragraphLines.append(candidate)
                index += 1
            }
            result.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return result
    }

    private static func sanitize(_ value: AttributedString) -> AttributedString {
        var rendered = value
        for run in rendered.runs {
            guard let link = run.link else { continue }
            let components = URLComponents(url: link, resolvingAgainstBaseURL: false)
            let allowed = components?.scheme?.lowercased() == "https"
                && components?.user == nil
                && components?.password == nil
            if !allowed { rendered[run.range].link = nil }
        }
        return rendered
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markerCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(markerCount) else { return nil }
        let remainder = line.dropFirst(markerCount)
        guard remainder.first?.isWhitespace == true else { return nil }
        return (markerCount, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func unorderedItem(from line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let prefix = line.prefix(2)
        guard prefix == "- " || prefix == "* " || prefix == "+ " else { return nil }
        return String(line.dropFirst(2))
    }

    private static func orderedItem(from line: String) -> String? {
        guard let period = line.firstIndex(of: "."), period != line.startIndex else { return nil }
        let number = line[..<period]
        guard number.allSatisfy(\.isNumber) else { return nil }
        let afterPeriod = line.index(after: period)
        guard afterPeriod < line.endIndex, line[afterPeriod].isWhitespace else { return nil }
        return String(line[line.index(after: afterPeriod)...])
    }

    private static func isDivider(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        return compact.count >= 3 && (compact.allSatisfy { $0 == "-" }
            || compact.allSatisfy { $0 == "*" }
            || compact.allSatisfy { $0 == "_" })
    }

    private static func startsBlock(_ line: String) -> Bool {
        line.hasPrefix("```")
            || heading(from: line) != nil
            || unorderedItem(from: line) != nil
            || orderedItem(from: line) != nil
            || line.hasPrefix(">")
            || isDivider(line)
    }
}

private extension AppVersion {
    var updateDisplayName: String {
        var values = components
        while values.count < 3 { values.append(0) }
        return values.map(String.init).joined(separator: ".")
    }
}

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

    enum HistoryState {
        case idle
        case loading
        case loaded([SoftwareUpdateHistoryEntry])
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var historyState: HistoryState = .idle

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

    var historyEntries: [SoftwareUpdateHistoryEntry] {
        guard case .loaded(let entries) = historyState else { return [] }
        return entries
    }

    var availableRelease: SoftwareUpdateRelease? {
        switch state {
        case .available(let release), .downloading(let release): return release
        case .ready(let prepared): return prepared.release
        default: return nil
        }
    }

    func checkIfNeeded() {
        guard case .idle = state else { return }
        check()
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

    func loadHistoryIfNeeded() {
        guard case .idle = historyState else { return }
        loadHistory()
    }

    func loadHistory() {
        historyState = .loading
        Task {
            do {
                historyState = .loaded(try await service.releaseHistory())
            } catch {
                historyState = .failed(error.localizedDescription)
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
    @State private var selectedReleaseID: String?
    @State private var confirmsRestart = false

    var body: some View {
        VStack(spacing: 0) {
            updateStatus
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()

            HSplitView {
                releaseList
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

                releaseDetails
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Updates")
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            controller.checkIfNeeded()
            controller.loadHistoryIfNeeded()
            selectPreferredRelease()
        }
        .onChange(of: controller.historyEntries.map(\.id)) { _ in
            selectPreferredRelease()
        }
        .confirmationDialog("Install the update and restart?", isPresented: $confirmsRestart) {
            if case .ready(let prepared) = controller.state {
                Button("Install and Restart") { controller.installAndRestart(prepared) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The account manager will close and reopen. Saved accounts, encrypted notes, groups, games, and sign-ins will stay in place.")
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch controller.state {
        case .idle:
            statusRow(
                title: "Installed version \(controller.currentVersion)",
                detail: "Check GitHub for a newer final release."
            ) {
                Button("Check for Updates") { controller.check() }
                    .buttonStyle(.borderedProminent)
            }
        case .checking:
            statusRow(
                title: "Checking for updates",
                detail: "Installed version \(controller.currentVersion)"
            ) {
                ProgressView().controlSize(.small)
            }
        case .upToDate(let version):
            statusRow(
                title: "You're up to date",
                detail: "Version \(version) is installed.",
                systemImage: "checkmark.circle.fill"
            ) {
                Button("Check Again") { controller.check() }
            }
        case .available(let release):
            statusRow(
                title: "Version \(release.version.updateDisplayName) is available",
                detail: release.title,
                systemImage: "arrow.down.circle.fill"
            ) {
                Button("Download Update") { controller.download(release) }
                    .buttonStyle(.borderedProminent)
            }
        case .downloading(let release):
            statusRow(
                title: "Downloading version \(release.version.updateDisplayName)",
                detail: "The app will verify the download before it can be installed."
            ) {
                ProgressView().controlSize(.small)
            }
        case .ready(let prepared):
            statusRow(
                title: "Version \(prepared.release.version.updateDisplayName) is ready",
                detail: "Restart the account manager to finish the update.",
                systemImage: "checkmark.seal.fill"
            ) {
                Button("Install and Restart") { confirmsRestart = true }
                    .buttonStyle(.borderedProminent)
            }
        case .installing:
            statusRow(
                title: "Installing the update",
                detail: "The account manager will reopen when installation finishes."
            ) {
                ProgressView().controlSize(.small)
            }
        case .failed(let message):
            statusRow(
                title: "Update check failed",
                detail: message,
                systemImage: "exclamationmark.triangle.fill"
            ) {
                Button("Try Again") { controller.check() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func statusRow<Actions: View>(
        title: String,
        detail: String,
        systemImage: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)
            actions()
        }
    }

    private var releaseList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Release History")
                    .font(.headline)
                Spacer()
                if case .loading = controller.historyState {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            switch controller.historyState {
            case .idle, .loading:
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading releases")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Text("Release history could not be loaded.")
                        .fontWeight(.medium)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try Again") { controller.loadHistory() }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .loaded(let entries):
                if entries.isEmpty {
                    Text("No final releases were found.")
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    List(entries, selection: $selectedReleaseID) { entry in
                        ReleaseHistoryRow(
                            entry: entry,
                            isInstalled: entry.version == AppVersion(controller.currentVersion),
                            isAvailable: entry.version == controller.availableRelease?.version
                        )
                        .tag(entry.id)
                    }
                    .listStyle(.sidebar)
                }
            }
        }
    }

    @ViewBuilder
    private var releaseDetails: some View {
        if let entry = selectedRelease {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 10) {
                            Text("Version \(entry.version.updateDisplayName)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let publishedAt = entry.publishedAt {
                                Text(publishedAt, format: .dateTime.month(.wide).day().year())
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(entry.title)
                            .font(.title2.weight(.semibold))
                            .textSelection(.enabled)
                    }

                    if entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("This release does not include a description.")
                            .foregroundStyle(.secondary)
                    } else {
                        ReleaseNotesMarkdownView(source: entry.notes)
                    }

                    Link(destination: entry.pageURL) {
                        Label("View this release on GitHub", systemImage: "safari")
                    }

                    DisclosureGroup("How updates stay safe") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The app downloads final releases only from this project's public GitHub page. It checks the published file fingerprint and confirms that the new app has the same signing identity before installing it.")
                            Text("The previous app version stays in a hidden backup beside the installed app. A failed replacement restores it automatically.")
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    }
                }
                .padding(24)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text("Choose a Release")
                    .font(.title3.weight(.semibold))
                Text("Select a version to read its update description.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedRelease: SoftwareUpdateHistoryEntry? {
        guard let selectedReleaseID else { return nil }
        return controller.historyEntries.first { $0.id == selectedReleaseID }
    }

    private func selectPreferredRelease() {
        guard !controller.historyEntries.isEmpty else { return }
        if let selectedReleaseID,
           controller.historyEntries.contains(where: { $0.id == selectedReleaseID }) { return }
        selectedReleaseID = controller.availableRelease?.version.description
            ?? controller.historyEntries.first?.id
    }
}

private struct ReleaseNotesMarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(ReleaseNotesMarkdown.blocks(in: source).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: ReleaseNotesMarkdown.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(ReleaseNotesMarkdown.parseInline(text))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 4 : 0)
        case .paragraph(let text):
            Text(ReleaseNotesMarkdown.parseInline(text))
                .fixedSize(horizontal: false, vertical: true)
        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(ReleaseNotesMarkdown.parseInline(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(ReleaseNotesMarkdown.parseInline(item))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            Text(ReleaseNotesMarkdown.parseInline(text))
                .italic()
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
        case .code(let text):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.semibold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }
}

private struct ReleaseHistoryRow: View {
    let entry: SoftwareUpdateHistoryEntry
    let isInstalled: Bool
    let isAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Version \(entry.version.updateDisplayName)")
                    .fontWeight(.medium)
                Spacer(minLength: 4)
                if isAvailable {
                    Text("Available")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if isInstalled {
                    Label("Installed", systemImage: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let publishedAt = entry.publishedAt {
                Text(publishedAt, format: .dateTime.month().day().year())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct SoftwareUpdateNotice: View {
    @ObservedObject var controller: SoftwareUpdateController
    let onShowDetails: () -> Void

    @AppStorage("dismissedUpdateNoticeVersion") private var dismissedVersion = ""
    @State private var confirmsRestart = false

    var body: some View {
        Group {
            switch controller.state {
            case .available(let release) where dismissedVersion != release.version.description:
                notice(
                    title: "Update available",
                    detail: release.title,
                    canDismiss: true
                ) {
                    Button("Update") { controller.download(release) }
                        .buttonStyle(.borderedProminent)
                    Button("Details", action: onShowDetails)
                } onDismiss: {
                    dismissedVersion = release.version.description
                }
            case .downloading(let release):
                notice(
                    title: "Downloading update",
                    detail: "Version \(release.version.updateDisplayName) will be verified before installation."
                ) {
                    ProgressView().controlSize(.small)
                    Button("Details", action: onShowDetails)
                }
            case .ready(let prepared):
                notice(
                    title: "Update ready",
                    detail: "Restart to install version \(prepared.release.version.updateDisplayName)."
                ) {
                    Button("Restart") { confirmsRestart = true }
                        .buttonStyle(.borderedProminent)
                    Button("Details", action: onShowDetails)
                }
            default:
                EmptyView()
            }
        }
        .confirmationDialog("Install the update and restart?", isPresented: $confirmsRestart) {
            if case .ready(let prepared) = controller.state {
                Button("Install and Restart") { controller.installAndRestart(prepared) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The account manager will close and reopen. Saved accounts, encrypted notes, groups, games, and sign-ins will stay in place.")
        }
    }

    private func notice<Actions: View>(
        title: String,
        detail: String,
        canDismiss: Bool = false,
        @ViewBuilder actions: () -> Actions,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                actions()
            }
            .controlSize(.small)
            .fixedSize(horizontal: true, vertical: false)

            if canDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss update notice")
                .help("Dismiss this update notice")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
