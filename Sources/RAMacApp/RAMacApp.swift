import AppKit
import Combine
import RAMacCore
import SwiftUI

final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@MainActor
final class ApplicationNoticePresenter: ObservableObject {
    private let store: AccountStore
    private var noticeChanges: AnyCancellable?
    private var activeWindows: AnyCancellable?
    private var presenting = false

    init(store: AccountStore) {
        self.store = store
        noticeChanges = store.$notice.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.presentNext()
        }
        activeWindows = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.presentNext() }
    }

    func presentNext() {
        guard !presenting, let notice = store.notice, var window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        while let sheet = window.attachedSheet { window = sheet }
        let alert = NSAlert()
        alert.messageText = notice.title
        alert.informativeText = notice.message
        alert.addButton(withTitle: "OK")
        presenting = true
        alert.beginSheetModal(for: window) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.store.notice?.id == notice.id { self.store.notice = nil }
                self.presenting = false
                self.presentNext()
            }
        }
    }
}

@main
struct RAMacApp: App {
    @NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self) private var lifecycleDelegate
    @StateObject private var store: AccountStore
    @StateObject private var updater: SoftwareUpdateController
    @StateObject private var noticePresenter: ApplicationNoticePresenter

    init() {
        #if RAM_KEYCHAIN_FIXTURE
        if let result = KeychainContinuityFixture.run(CommandLine.arguments) {
            exit(result)
        }
        #endif
        NSWindow.allowsAutomaticWindowTabbing = false
        let accountStore: AccountStore
        if AppSmokeTestConfiguration.isEnabled {
            let directory = AppSmokeTestConfiguration.dataDirectory
            let storage = AppSmokeTestStorage()
            accountStore = AccountStore(
                repository: AccountRepository(dataDirectory: directory),
                vault: storage,
                launcher: ParallelRobloxLauncher(
                    instancesRoot: directory.appendingPathComponent("Instances", isDirectory: true)
                ),
                windowLayout: WindowLayoutController(repository: storage)
            )
        } else {
            accountStore = AccountStore()
        }
        _store = StateObject(wrappedValue: accountStore)
        _noticePresenter = StateObject(wrappedValue: ApplicationNoticePresenter(store: accountStore))
        _updater = StateObject(wrappedValue: SoftwareUpdateController())
    }

    var body: some Scene {
        Window("Accounts", id: "accounts") {
            ContentView(
                store: store,
                updater: updater,
                performsAutomaticChecks: !AppSmokeTestConfiguration.isEnabled
            )
                .frame(minWidth: 900, minHeight: 600)
                .background(WindowTabbingDisabler())
                .dismissTextInputOnOutsideClick()
                .onAppear { noticePresenter.presentNext() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 720)
        .commands {
            V1ViewCommands()
        }

        Window("Add Roblox Account", id: "add-account") {
            AddAccountView(store: store)
                .dismissTextInputOnOutsideClick()
        }
        .defaultSize(width: 860, height: 660)

        Window("Joinable Players", id: "joinable-players") {
            JoinablePlayersView(store: store)
                .dismissTextInputOnOutsideClick()
        }
        .defaultSize(width: 1160, height: 720)

        Window("Launch Sets", id: "launch-sets") {
            LaunchSetsView(store: store)
                .dismissTextInputOnOutsideClick()
        }
        .defaultSize(width: 980, height: 680)

        Window("Running Accounts", id: "running-accounts") {
            RunningAccountsView(store: store)
        }
        .defaultSize(width: 590, height: 440)

        Window("Game Library", id: "game-library") {
            GameLibraryView(store: store)
                .dismissTextInputOnOutsideClick()
        }
        .defaultSize(width: 900, height: 620)

        Window("Launch Defaults", id: "window-layout") {
            WindowLayoutView(store: store, controller: store.windowLayout)
                .dismissTextInputOnOutsideClick()
        }
        .defaultSize(width: 1100, height: 650)

        Window("Send Feedback", id: "feedback") {
            FeedbackView()
                .dismissTextInputOnOutsideClick()
        }
        .defaultSize(width: 860, height: 660)

        Window("Diagnostics and Backup", id: "diagnostics") {
            DiagnosticsView(store: store)
                .dismissTextInputOnOutsideClick()
        }
        .defaultSize(width: 760, height: 700)

        Window("Software Update", id: "software-update") {
            SoftwareUpdateView(controller: updater)
        }
        .defaultSize(width: 860, height: 640)

        WindowGroup(for: AccountWebsiteRequest.self) { $request in
            if let request {
                AccountWebsiteWindow(store: store, request: request)
                    .dismissTextInputOnOutsideClick()
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1050, height: 760)
    }
}

private struct V1ViewCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Account") { openWindow(id: "add-account") }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Tools") {
            ToolsMenuItems(usesKeyboardShortcuts: true)
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { openWindow(id: "software-update") }
        }
    }
}

struct ToolsMenuItems: View {
    @Environment(\.openWindow) private var openWindow
    var usesKeyboardShortcuts = false

    var body: some View {
        Button("Joinable Players") { openWindow(id: "joinable-players") }
            .keyboardShortcut(usesKeyboardShortcuts ? KeyboardShortcut("f", modifiers: [.command, .shift]) : nil)
        Button("Launch Sets") { openWindow(id: "launch-sets") }
        Button("Game Library") { openWindow(id: "game-library") }
        Button("Running Accounts") { openWindow(id: "running-accounts") }
        Button("Launch Defaults") { openWindow(id: "window-layout") }
            .keyboardShortcut(usesKeyboardShortcuts ? KeyboardShortcut("l", modifiers: [.command, .shift]) : nil)
        Button("Send Feedback") { openWindow(id: "feedback") }
        Button("Diagnostics and Backup") { openWindow(id: "diagnostics") }
    }
}

private struct WindowTabbingDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWindow(for: view)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if window.tabbedWindows != nil {
                window.toggleTabBar(nil)
            }
            window.tabbingIdentifier = ""
            window.tabbingMode = .disallowed
        }
    }
}
