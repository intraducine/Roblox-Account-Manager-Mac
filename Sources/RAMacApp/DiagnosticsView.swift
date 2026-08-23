import AppKit
import RAMacCore
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: AccountStore
    @State private var report: DiagnosticReport?
    @State private var isRunning = false
    @State private var showsPrivateExportWarning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Local Check") {
                    Text("Run a local check for Roblox, app copies, storage, saved sign-ins, and Roblox services. The report never includes sign-in secrets, launch tickets, or private links.")
                        .foregroundStyle(.secondary)
                    Button(isRunning ? "Running Check" : "Run Check") { Task { await runCheck() } }
                        .disabled(isRunning)
                }
                if let report {
                    Section("Results") {
                        ForEach(report.checks) { check in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: symbol(check.status))
                                    .foregroundStyle(color(check.status))
                                    .accessibilityLabel(check.status.rawValue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(check.title).fontWeight(.medium)
                                    Text(check.message).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Export Redacted Report") { exportReport(report) }
                    }
                }
                Section("Backup and Restore") {
                    Text("Normal backups include account details, groups, recent games, favorites, and Launch Sets. They exclude encrypted profile notes, Roblox sign-ins, and private server links. Import keeps the notes and sign-ins already stored in Keychain on this Mac.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Export Backup") { exportBackup(includePrivateLinks: false) }
                        Button("Import Backup") { importBackup() }
                        Spacer()
                        Button("Export with Private Links…") { showsPrivateExportWarning = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Diagnostics and Backup")
        }
        .frame(minWidth: 720, minHeight: 620)
        .confirmationDialog("Include private server links?", isPresented: $showsPrivateExportWarning) {
            Button("Export with Private Links", role: .destructive) { exportBackup(includePrivateLinks: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Private server links can grant access. Protect this backup like a password.")
        }
        .alert(item: $store.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
        }
    }

    private func runCheck() async {
        isRunning = true
        let service = DiagnosticService(
            accountRepository: AccountRepository(),
            vault: KeychainVault()
        )
        report = await service.run()
        isRunning = false
    }

    private func exportReport(_ report: DiagnosticReport) {
        do { try save(data: report.exportData(), suggestedName: "Roblox-Account-Manager-Diagnostics.json") }
        catch { store.notice = .init(title: "Report was not saved", message: error.localizedDescription) }
    }

    private func exportBackup(includePrivateLinks: Bool) {
        do {
            try save(
                data: store.exportMetadata(includePrivateLinks: includePrivateLinks),
                suggestedName: "Roblox-Account-Manager-Backup.json"
            )
        } catch { store.notice = .init(title: "Backup was not saved", message: error.localizedDescription) }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = values.fileSize,
                  fileSize <= MetadataArchiveService.maximumArchiveBytes else {
                throw MetadataArchiveService.ArchiveError.tooLarge
            }
            let count = try store.importMetadata(Data(contentsOf: url))
            store.notice = .init(
                title: "Backup imported",
                message: count == 0 ? "Existing account details were updated. Saved sign-ins and encrypted profile notes were not changed." : "Imported \(count) signed-out account\(count == 1 ? "" : "s"). Saved sign-ins and encrypted profile notes were not changed."
            )
        } catch { store.notice = .init(title: "Backup could not be imported", message: error.localizedDescription) }
    }

    private func save(data: Data, suggestedName: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func symbol(_ status: DiagnosticCheckStatus) -> String {
        switch status { case .passed: return "checkmark.circle"; case .warning: return "exclamationmark.triangle"; case .failed: return "xmark.circle" }
    }
    private func color(_ status: DiagnosticCheckStatus) -> Color {
        switch status { case .passed: return .secondary; case .warning: return .orange; case .failed: return .red }
    }
}
