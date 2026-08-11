import AppKit
import SwiftUI

@main
struct RAMacApp: App {
    @StateObject private var store = AccountStore()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 600)
                .background(WindowTabbingDisabler())
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
            V1ViewCommands()
        }

        Window("Joinable Players", id: "joinable-players") {
            JoinablePlayersView(store: store)
        }
        .defaultSize(width: 1160, height: 720)

        Window("Launch Sets", id: "launch-sets") {
            LaunchSetsView(store: store)
        }
        .defaultSize(width: 980, height: 680)

        Window("Diagnostics and Backup", id: "diagnostics") {
            DiagnosticsView(store: store)
        }
        .defaultSize(width: 760, height: 700)

        WindowGroup(for: AccountWebsiteRequest.self) { $request in
            if let request {
                AccountWebsiteWindow(store: store, request: request)
            }
        }
        .defaultSize(width: 1050, height: 760)
    }
}

private struct V1ViewCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Joinable Players") { openWindow(id: "joinable-players") }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Launch Sets") { openWindow(id: "launch-sets") }
            Button("Diagnostics and Backup") { openWindow(id: "diagnostics") }
        }
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
