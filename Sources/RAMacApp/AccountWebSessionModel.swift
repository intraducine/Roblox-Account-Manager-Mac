import AppKit
import Foundation
import RAMacCore
import WebKit

enum AccountWebsiteDestination: Codable, Hashable {
    case home
    case profile
    case settings
    case security
    case playerProfile(Int64)

    var url: URL {
        switch self {
        case .home: return URL(string: "https://www.roblox.com/home")!
        case .profile: return URL(string: "https://www.roblox.com/users/profile")!
        case .settings: return URL(string: "https://www.roblox.com/my/account")!
        case .security: return URL(string: "https://www.roblox.com/my/account#!/security")!
        case .playerProfile(let userID): return URL(string: "https://www.roblox.com/users/\(userID)/profile")!
        }
    }
}

struct AccountWebsiteRequest: Codable, Hashable {
    let accountID: UUID
    let destination: AccountWebsiteDestination
}

@MainActor
final class AccountWebSessionModel: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pendingExternalURL: URL?
    @Published var errorMessage: String?

    private(set) weak var webView: WKWebView?
    func configure(session: String, destination: URL) -> WKWebView {
        let normalizedSession = RobloxAPIClient.normalizedCookie(from: session)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.allowsMagnification = true
        webView = view

        let properties: [HTTPCookiePropertyKey: Any] = [
            .domain: ".roblox.com",
            .path: "/",
            .name: ".ROBLOSECURITY",
            .value: normalizedSession,
            .secure: true,
            .expires: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
        ]
        if let cookie = HTTPCookie(properties: properties) {
            configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { [weak view] in
                view?.load(URLRequest(url: destination))
            }
        } else {
            view.load(URLRequest(url: destination))
        }
        return view
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() {
        errorMessage = nil
        webView?.reload()
    }
    func load(_ destination: AccountWebsiteDestination) {
        errorMessage = nil
        webView?.load(URLRequest(url: destination.url))
    }

    func currentSession() async -> String? {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return nil }
        return await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies.first(where: {
                    $0.name == ".ROBLOSECURITY"
                        && ($0.domain == "roblox.com" || $0.domain.hasSuffix(".roblox.com"))
                })?.value)
            }
        }
    }

    func clear() async {
        guard let dataStore = webView?.configuration.websiteDataStore else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { continuation.resume() }
        }
        webView?.navigationDelegate = nil
        webView = nil
    }

    func openPendingExternalURL() {
        guard let pendingExternalURL else { return }
        NSWorkspace.shared.open(pendingExternalURL)
        self.pendingExternalURL = nil
    }

    private func updateNavigationState(_ webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }
}

extension AccountWebSessionModel: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let host = url.host?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        let isRoblox = url.scheme?.lowercased() == "https"
            && (host == "roblox.com" || host.hasSuffix(".roblox.com"))
        guard isRoblox else {
            decisionHandler(.cancel)
            pendingExternalURL = url
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        updateNavigationState(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState(webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        errorMessage = error.localizedDescription
        updateNavigationState(webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        errorMessage = error.localizedDescription
        updateNavigationState(webView)
    }
}
