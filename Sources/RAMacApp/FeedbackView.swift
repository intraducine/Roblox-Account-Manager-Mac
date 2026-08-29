import AppKit
import SwiftUI
import WebKit

struct FeedbackMetadata: Equatable {
    let appVersion: String
    let build: String
    let macOSVersion: String
    let processor: String

    static var current: FeedbackMetadata {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info["CFBundleVersion"] as? String ?? "Unknown"
        let system = ProcessInfo.processInfo.operatingSystemVersion

        #if arch(arm64)
        let processor = "Apple silicon"
        #elseif arch(x86_64)
        let processor = "Intel"
        #else
        let processor = "Unknown"
        #endif

        return FeedbackMetadata(
            appVersion: version,
            build: build,
            macOSVersion: "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            processor: processor
        )
    }

    var versionDescription: String {
        "Version \(appVersion) (\(build))"
    }

    var systemDescription: String {
        "\(macOSVersion), \(processor)"
    }
}

enum FeedbackConfiguration {
    static let formID = "6867A5"

    static func embedURL(
        formID: String = formID,
        metadata: FeedbackMetadata,
        includesAppVersion: Bool,
        includesSystemInformation: Bool
    ) -> URL? {
        guard !formID.isEmpty, formID != "TALLY_FORM_ID" else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "tally.so"
        components.path = "/embed/\(formID)"

        var items = [
            URLQueryItem(name: "hideTitle", value: "1"),
            URLQueryItem(name: "transparentBackground", value: "1")
        ]
        if includesAppVersion {
            items.append(URLQueryItem(name: "app_version", value: metadata.versionDescription))
        }
        if includesSystemInformation {
            items.append(URLQueryItem(name: "system", value: metadata.systemDescription))
        }
        components.queryItems = items
        return components.url
    }
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = FeedbackBrowserModel()
    @State private var includesAppVersion = true
    @State private var includesSystemInformation = false
    @State private var hasOpenedForm = false
    @State private var showsRestartConfirmation = false
    private let metadata = FeedbackMetadata.current

    private var formURL: URL? {
        FeedbackConfiguration.embedURL(
            metadata: metadata,
            includesAppVersion: includesAppVersion,
            includesSystemInformation: includesSystemInformation
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasOpenedForm, let formURL {
                    embeddedForm(formURL)
                } else {
                    consentView
                }
            }
            .navigationTitle("Send Feedback")
            .toolbar {
                ToolbarItemGroup(placement: .cancellationAction) {
                    if hasOpenedForm {
                        Button("Restart Form") {
                            showsRestartConfirmation = true
                        }
                    }
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 600)
        .confirmationDialog(
            "Open this link in your default browser?",
            isPresented: Binding(
                get: { browser.pendingExternalURL != nil },
                set: { if !$0 { browser.pendingExternalURL = nil } }
            )
        ) {
            Button("Open in Default Browser") { browser.openPendingExternalURL() }
            Button("Cancel", role: .cancel) { browser.pendingExternalURL = nil }
        } message: {
            Text("The feedback form requested a secure page on \(browser.pendingExternalURL?.host ?? "another site").")
        }
        .confirmationDialog(
            "Restart the feedback form?",
            isPresented: $showsRestartConfirmation
        ) {
            Button("Restart Form", role: .destructive) {
                browser.reset()
                hasOpenedForm = false
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Restarting clears anything already entered in the form.")
        }
    }

    private var consentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Send feedback without leaving the app")
                    .font(.title2.weight(.semibold))
                Text("The form is provided by Tally. Choose which technical details to include before it loads.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupBox("Optional technical details") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle(isOn: $includesAppVersion) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Include app version and build")
                            Text(metadata.versionDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: $includesSystemInformation) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Include macOS version and processor")
                            Text(metadata.systemDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppGeometry.panelEdgeControlInset)
            }

            Text("The app never includes Roblox account names, session values, authentication tickets, private-server links, access codes, or launch URLs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Spacer()
                Button("Continue to Feedback Form") {
                    hasOpenedForm = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(formURL == nil)
            }

            if formURL == nil {
                Text("The Tally feedback form is not configured in this build.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, AppGeometry.windowEdgeControlInset)
        .padding(.top, AppGeometry.windowContentInset)
        .padding(.bottom, AppGeometry.windowEdgeControlInset)
    }

    private func embeddedForm(_ url: URL) -> some View {
        ZStack {
            TallyFeedbackWebView(model: browser, url: url)

            if browser.isLoading {
                ProgressView()
                    .controlSize(.large)
            } else if let errorMessage = browser.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Feedback Form Could Not Load")
                        .font(.title2.weight(.semibold))
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    Button("Try Again") { browser.reload() }
                }
                .padding(28)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

}

@MainActor
final class FeedbackBrowserModel: ObservableObject {
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var pendingExternalURL: URL?
    weak var webView: WKWebView?

    func configure(url: URL, coordinator: WKNavigationDelegate & WKUIDelegate) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        view.allowsMagnification = true
        webView = view
        view.load(URLRequest(url: url))
        return view
    }

    func reload() {
        errorMessage = nil
        isLoading = true
        webView?.reload()
    }

    func reset() {
        webView?.stopLoading()
        webView = nil
        pendingExternalURL = nil
        errorMessage = nil
        isLoading = true
    }

    func openPendingExternalURL() {
        guard let url = Self.safeExternalURL(pendingExternalURL) else {
            pendingExternalURL = nil
            return
        }
        pendingExternalURL = nil
        NSWorkspace.shared.open(url)
    }

    nonisolated static func safeExternalURL(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil,
              url.password == nil else { return nil }
        return url
    }

    nonisolated static func allowsMainFrameNavigation(to url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "tally.so"
            && url.path == "/embed/\(FeedbackConfiguration.formID)"
    }
}

private struct TallyFeedbackWebView: NSViewRepresentable {
    @ObservedObject var model: FeedbackBrowserModel
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        model.configure(url: url, coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: FeedbackBrowserModel

        init(model: FeedbackBrowserModel) {
            self.model = model
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame?.isMainFrame == false {
                decisionHandler(
                    navigationAction.request.url?.scheme?.lowercased() == "https"
                        ? .allow
                        : .cancel
                )
                return
            }

            if FeedbackBrowserModel.allowsMainFrameNavigation(to: navigationAction.request.url) {
                decisionHandler(.allow)
            } else {
                if let url = FeedbackBrowserModel.safeExternalURL(navigationAction.request.url) {
                    Task { @MainActor in model.pendingExternalURL = url }
                }
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = FeedbackBrowserModel.safeExternalURL(navigationAction.request.url) {
                Task { @MainActor in model.pendingExternalURL = url }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                model.errorMessage = nil
                model.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in model.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            Task { @MainActor in
                model.isLoading = false
                model.errorMessage = error.localizedDescription
            }
        }
    }
}
