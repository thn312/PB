import Combine
import Foundation
import Network
import Security
import WebKit

struct ProxySettings {
    var type = "socks5" // "socks5" | "http"
    var host = ""
    var port = 1080
    var user = ""
    var pass = ""

    static func load() -> ProxySettings {
        let d = UserDefaults.standard
        return ProxySettings(
            type: d.string(forKey: "p.type") ?? "socks5",
            host: d.string(forKey: "p.host") ?? "",
            port: d.object(forKey: "p.port") as? Int ?? 1080,
            user: d.string(forKey: "p.user") ?? "",
            pass: Keychain.get("p.pass"))
    }

    func save() {
        let d = UserDefaults.standard
        d.set(type, forKey: "p.type"); d.set(host, forKey: "p.host")
        d.set(port, forKey: "p.port"); d.set(user, forKey: "p.user")
        Keychain.set("p.pass", pass)
    }

    func configuration() -> ProxyConfiguration? {
        guard !host.isEmpty, let p = UInt16(exactly: port), let port = NWEndpoint.Port(rawValue: p) else { return nil }
        let ep = NWEndpoint.hostPort(host: .init(host), port: port)
        let c = type == "http" ? ProxyConfiguration(httpCONNECTProxy: ep) : ProxyConfiguration(socksv5Proxy: ep)
        if !user.isEmpty { c.applyCredential(username: user, password: pass) }
        return c
    }
}

enum Keychain {
    private static func base(_ k: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: k]
    }
    static func get(_ k: String) -> String {
        var q = base(k); q[kSecReturnData as String] = true
        var r: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &r)
        return (r as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    static func set(_ k: String, _ v: String) {
        SecItemDelete(base(k) as CFDictionary)
        var q = base(k); q[kSecValueData as String] = Data(v.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Where the proxy's exit IP is, looked up *through* the proxy.
struct Geo: Decodable {
    let ip: String, city: String, region: String, country: String, loc: String, timezone: String

    var coords: (Double, Double)? {
        let p = loc.split(separator: ",").compactMap { Double($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }

    static func lookup(via proxy: ProxyConfiguration) async throws -> Geo {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.proxyConfigurations = [proxy]
        cfg.timeoutIntervalForRequest = 15
        let s = URLSession(configuration: cfg)
        defer { s.finishTasksAndInvalidate() }
        let (data, _) = try await s.data(from: URL(string: "https://ipinfo.io/json")!)
        return try JSONDecoder().decode(Geo.self, from: data)
    }
}

struct BrowserError: LocalizedError {
    let errorDescription: String?
}

@MainActor
final class Browser: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var current: Tab?
    @Published var status = "Not connected"
    @Published var connecting = false
    @Published var adblock = UserDefaults.standard.object(forKey: "adblock") as? Bool ?? true {
        didSet { UserDefaults.standard.set(adblock, forKey: "adblock"); applyAdblock(reload: true) }
    }
    private var config: WKWebViewConfiguration?
    private var adRules: WKContentRuleList?

    /// Fail closed: no tab exists until the proxy is verified, so the real IP is never used.
    func connect() async {
        tabs = []; current = nil; config = nil
        guard let proxy = ProxySettings.load().configuration() else {
            status = "No proxy set"
            return
        }
        status = "Checking proxy…"
        connecting = true
        defer { connecting = false }
        do {
            let geo = try await Geo.lookup(via: proxy)
            guard let c = geo.coords, TimeZone(identifier: geo.timezone) != nil else {
                throw BrowserError(errorDescription: "Could not read the proxy location")
            }
            config = try makeConfig(proxy: proxy, lat: c.0, lon: c.1, tz: geo.timezone)
            if adRules == nil { adRules = try? await compileAdRules() } // a broken blocklist must not stop browsing
            applyAdblock(reload: false)
            status = "\(geo.country == "US" ? "🇺🇸" : "⚠️ \(geo.country)") \(geo.city), \(geo.region) · \(geo.ip)"
            newTab("https://browserleaks.com/ip")
        } catch {
            status = "Proxy error: \(error.localizedDescription)"
        }
    }

    private func makeConfig(proxy: ProxyConfiguration, lat: Double, lon: Double, tz: String) throws -> WKWebViewConfiguration {
        guard let url = Bundle.main.url(forResource: "spoof", withExtension: "js") else {
            throw BrowserError(errorDescription: "spoof.js is missing")
        }
        // JSON-encode values from the network so they can't inject JS.
        let cfg = String(decoding: try JSONSerialization.data(withJSONObject: ["lat": lat, "lon": lon, "tz": tz]), as: UTF8.self)
        // Wrapped so `C` never collides with a page's own globals.
        let js = "(C => {\n" + (try String(contentsOf: url, encoding: .utf8)) + "\n})(\(cfg));"

        let store = WKWebsiteDataStore.default()
        store.proxyConfigurations = [proxy]
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.userContentController.addUserScript(
            WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        return config
    }

    // shortcut: recompiles the ~3.5k-rule list on every launch (well under a second); cache by app version if it gets slow.
    private func compileAdRules() async throws -> WKContentRuleList? {
        guard let url = Bundle.main.url(forResource: "blocklist", withExtension: "json") else {
            throw BrowserError(errorDescription: "blocklist.json is missing")
        }
        let json = try String(contentsOf: url, encoding: .utf8)
        return try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "ads", encodedContentRuleList: json)
    }

    private func applyAdblock(reload: Bool) {
        var controllers = tabs.map { $0.webView.configuration.userContentController }
        if let c = config?.userContentController { controllers.append(c) }
        for c in controllers {
            c.removeAllContentRuleLists()
            if adblock, let adRules { c.add(adRules) }
        }
        if reload { current?.webView.reload() }
    }

    @discardableResult
    func newTab(_ address: String = "https://www.google.com", config: WKWebViewConfiguration? = nil) -> Tab? {
        guard let config = config ?? self.config else { return nil }
        let tab = Tab(config: config, browser: self)
        tabs.append(tab)
        current = tab
        if !address.isEmpty { tab.go(address) }
        return tab
    }

    func close(_ tab: Tab) {
        tab.webView.stopLoading()
        tabs.removeAll { $0 === tab }
        if current === tab { current = tabs.last }
        if tabs.isEmpty { newTab() }
    }
}

@MainActor
final class Tab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    weak var browser: Browser?
    @Published var title = ""
    @Published var url: URL?
    @Published var progress = 0.0
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var error = ""

    init(config: WKWebViewConfiguration, browser: Browser) {
        webView = WKWebView(frame: .zero, configuration: config)
        self.browser = browser
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.publisher(for: \.title).map { $0 ?? "" }.assign(to: &$title)
        webView.publisher(for: \.url).assign(to: &$url)
        webView.publisher(for: \.estimatedProgress).assign(to: &$progress)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
    }

    func go(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let url: URL?
        if t.contains("://") {
            url = URL(string: t)
        } else if t.contains(".") && !t.contains(" ") {
            url = URL(string: "https://" + t)
        } else {
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: t)]
            url = c.url
        }
        guard let url else { error = "Invalid address: \(t)"; return }
        error = ""
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        error = ""
    }

    // Never hand links to other apps (X, YouTube…): they'd run outside the proxy with the real IP.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else { return decisionHandler(.cancel) }
        // shortcut: allow+2 is WebKit's private "allow without trying app link"; if a future iOS drops it, links may open apps again.
        decisionHandler(WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    private func report(_ e: Error) {
        let e = e as NSError
        if e.code == NSURLErrorCancelled { return } // a newer navigation replaced this one
        if e.domain == "WebKitErrorDomain" && e.code == 102 { return } // we cancelled it in decidePolicyFor (e.g. twitter:// app link)
        let url = e.userInfo[NSURLErrorFailingURLStringErrorKey] as? String ?? ""
        error = "⚠️ \(e.localizedDescription) (\(e.domain) \(e.code)) \(url)"
    }

    // target="_blank" and window.open: open a new tab. WebKit requires using the given configuration.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        browser?.newTab("", config: configuration)?.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        browser?.close(self)
    }
}
