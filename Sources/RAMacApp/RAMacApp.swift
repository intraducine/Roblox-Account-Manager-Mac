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
