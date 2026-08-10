import SwiftUI
import WebKit

@MainActor
final class LoginBrowserModel: ObservableObject {
    @Published var isLoading = true
    @Published var hasSession = false
    weak var webView: WKWebView?

    func updateSessionState() {
        webView?.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let found = cookies.contains { $0.name == ".ROBLOSECURITY" && !$0.value.isEmpty }
            Task { @MainActor in self.hasSession = found }
        }
    }

    func sessionCookie() async -> String? {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return nil }
        return await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies.first(where: { $0.name == ".ROBLOSECURITY" })?.value)
            }
        }
    }
}

struct RobloxLoginWebView: NSViewRepresentable {
    @ObservedObject var model: LoginBrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsMagnification = true
        model.webView = view
        view.load(URLRequest(url: URL(string: "https://www.roblox.com/login")!))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: LoginBrowserModel

        init(model: LoginBrowserModel) { self.model = model }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in model.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                model.isLoading = false
                model.updateSessionState()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in model.isLoading = false }
        }
    }
}
