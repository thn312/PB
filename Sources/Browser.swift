import Combine
import Foundation
import Network
import Security
import UIKit
import WebKit

struct ProxySettings: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var type = "socks5" // "socks5" | "http"
    var host = ""
    var port = 1080
    var user = ""
    var pass = "" // never encoded: lives in the Keychain

    private enum CodingKeys: String, CodingKey { case id, name, type, host, port, user }

    var label: String { name.isEmpty ? "\(host):\(port)" : name }

    func configuration() -> ProxyConfiguration? {
        guard !host.isEmpty, let p = UInt16(exactly: port), let port = NWEndpoint.Port(rawValue: p) else { return nil }
        let ep = NWEndpoint.hostPort(host: .init(host), port: port)
        let c = type == "http" ? ProxyConfiguration(httpCONNECTProxy: ep) : ProxyConfiguration(socksv5Proxy: ep)
        if !user.isEmpty { c.applyCredential(username: user, password: pass) }
        return c
    }
}

/// Saved proxies: the list in UserDefaults, each password in the Keychain under its id.
enum ProxyStore {
    private static let d = UserDefaults.standard

    static func all() -> [ProxySettings] {
        if let data = d.data(forKey: "proxies"), var list = try? JSONDecoder().decode([ProxySettings].self, from: data) {
            for i in list.indices { list[i].pass = Keychain.get("p.pass.\(list[i].id)") }
            return list
        }
        // Migrate the single proxy saved by older versions so the user doesn't have to re-enter it.
        guard let host = d.string(forKey: "p.host"), !host.isEmpty else { return [] }
        let old = ProxySettings(
            type: d.string(forKey: "p.type") ?? "socks5", host: host,
            port: d.object(forKey: "p.port") as? Int ?? 1080,
            user: d.string(forKey: "p.user") ?? "", pass: Keychain.get("p.pass"))
        save([old])
        activeID = old.id
        return [old]
    }

    static func save(_ list: [ProxySettings]) {
        for p in list { Keychain.set("p.pass.\(p.id)", p.pass) }
        d.set(try? JSONEncoder().encode(list), forKey: "proxies")
    }

    static func forget(_ p: ProxySettings) { Keychain.delete("p.pass.\(p.id)") }

    static var activeID: UUID? {
        get { d.string(forKey: "p.active").flatMap(UUID.init(uuidString:)) }
        set { d.set(newValue?.uuidString, forKey: "p.active") }
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
    static func delete(_ k: String) { SecItemDelete(base(k) as CFDictionary) }
    static func set(_ k: String, _ v: String) {
        delete(k)
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

/// youtube.js: the newest copy from GitHub (so YouTube fixes ship without reinstalling), else the bundled one.
enum YouTubeScript {
    static let remote = URL(string: "https://raw.githubusercontent.com/thn312/PB/main/Sources/youtube.js")!

    static func latest(via proxy: ProxyConfiguration?) async -> String {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.proxyConfigurations = proxy.map { [$0] } ?? [] // through the proxy, like everything else
        cfg.timeoutIntervalForRequest = 6
        let s = URLSession(configuration: cfg)
        defer { s.finishTasksAndInvalidate() }
        if let r = try? await s.data(from: remote), (r.1 as? HTTPURLResponse)?.statusCode == 200,
           let js = String(data: r.0, encoding: .utf8), js.hasPrefix("// PB youtube.js") {
            return js
        }
        return bundled
    }

    static var bundled: String {
        Bundle.main.url(forResource: "youtube", withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
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
        didSet { UserDefaults.standard.set(adblock, forKey: "adblock"); applyContent(reload: true) }
    }
    private var config: WKWebViewConfiguration?
    private var adRules: WKContentRuleList?
    private var spoofJS = ""
    private var youtubeJS = ""
    let history = HistoryStore()
    /// For app-side requests (search suggestions): same route as the tabs, proxy or direct.
    private(set) var session: URLSession?

    @Published var proxies = ProxyStore.all()
    @Published var activeID = ProxyStore.activeID
    /// No proxy: real IP, real location. Only ever on because the user picked it; a failing proxy never falls back to this.
    @Published var direct = UserDefaults.standard.bool(forKey: "p.direct")
    /// Off by default: links stay in PB instead of opening other apps, which would bypass the proxy.
    @Published var allowApps = UserDefaults.standard.bool(forKey: "allowApps") {
        didSet { UserDefaults.standard.set(allowApps, forKey: "allowApps") }
    }
    private var attempt = 0

    var activeProxy: ProxySettings? { proxies.first { $0.id == activeID } ?? proxies.first }

    func use(_ p: ProxySettings) {
        activeID = p.id
        ProxyStore.activeID = p.id
        setDirect(false)
    }

    func useDirect() { setDirect(true) }

    private func setDirect(_ on: Bool) {
        direct = on
        UserDefaults.standard.set(on, forKey: "p.direct")
        Task { await connect() }
    }

    func saveProxy(_ p: ProxySettings) {
        if let i = proxies.firstIndex(where: { $0.id == p.id }) { proxies[i] = p } else { proxies.append(p) }
        ProxyStore.save(proxies)
        if !direct && p.id == activeProxy?.id { use(p) } // edited the one in use (or the first one): reconnect with it
    }

    func deleteProxies(at offsets: IndexSet) {
        let gone = offsets.map { proxies[$0] }
        proxies.remove(atOffsets: offsets)
        gone.forEach(ProxyStore.forget)
        ProxyStore.save(proxies)
        if !direct && (gone.contains(where: { $0.id == activeID }) || proxies.isEmpty) {
            activeID = proxies.first?.id
            ProxyStore.activeID = activeID
            Task { await connect() }
        }
    }

    /// Fail closed: no tab exists until the proxy is verified, so the real IP is never used.
    func connect() async {
        attempt += 1
        let mine = attempt // a newer switch wins; an older lookup that finishes late is dropped
        tabs = []; current = nil; config = nil
        session?.invalidateAndCancel(); session = nil
        if direct {
            connecting = true
            defer { if mine == attempt { connecting = false } }
            status = "Connecting…"
            config = makeConfig(proxy: nil)
            spoofJS = "" // real IP, so keep the real location and timezone too
            youtubeJS = await YouTubeScript.latest(via: nil)
            if adRules == nil { adRules = try? await compileAdRules() }
            guard mine == attempt else { return }
            applyContent(reload: false)
            status = "⚠️ Direct · real IP (no proxy)"
            session = URLSession(configuration: .ephemeral)
            newTab()
            return
        }
        guard let p = activeProxy, let proxy = p.configuration() else {
            status = "No proxy set"
            return
        }
        activeID = p.id
        status = "Checking \(p.label)…"
        connecting = true
        defer { if mine == attempt { connecting = false } }
        do {
            async let yt = YouTubeScript.latest(via: proxy)
            let geo = try await Geo.lookup(via: proxy)
            guard mine == attempt else { return }
            guard let c = geo.coords, TimeZone(identifier: geo.timezone) != nil else {
                throw BrowserError(errorDescription: "Could not read the proxy location")
            }
            spoofJS = try makeSpoof(lat: c.0, lon: c.1, tz: geo.timezone)
            config = makeConfig(proxy: proxy)
            youtubeJS = await yt
            if adRules == nil { adRules = try? await compileAdRules() } // a broken blocklist must not stop browsing
            guard mine == attempt else { return }
            applyContent(reload: false)
            let flag = String(String.UnicodeScalarView(geo.country.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
            status = "\(flag) \(geo.city), \(geo.region) · \(geo.ip) · \(p.label)"
            let sc = URLSessionConfiguration.ephemeral
            sc.proxyConfigurations = [proxy]
            session = URLSession(configuration: sc)
            newTab("https://browserleaks.com/ip")
        } catch {
            guard mine == attempt else { return }
            status = "Proxy error (\(p.label)): \(error.localizedDescription)"
        }
    }

    private func makeSpoof(lat: Double, lon: Double, tz: String) throws -> String {
        guard let url = Bundle.main.url(forResource: "spoof", withExtension: "js") else {
            throw BrowserError(errorDescription: "spoof.js is missing")
        }
        // JSON-encode values from the network so they can't inject JS.
        let cfg = String(decoding: try JSONSerialization.data(withJSONObject: ["lat": lat, "lon": lon, "tz": tz]), as: UTF8.self)
        // Wrapped so `C` never collides with a page's own globals.
        return "(C => {\n" + (try String(contentsOf: url, encoding: .utf8)) + "\n})(\(cfg));"
    }

    private func makeConfig(proxy: ProxyConfiguration?) -> WKWebViewConfiguration {
        let store = WKWebsiteDataStore.default()
        store.proxyConfigurations = proxy.map { [$0] } ?? [] // shared store: always reset, or a direct session would keep the old proxy
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.allowsInlineMediaPlayback = true // like Safari: feed videos (X, etc.) play in the page, not fullscreen
        // Look exactly like Safari: a bare WKWebView UA lacks "Version/x Safari/604.1", which sites use to flag in-app browsers.
        let v = UIDevice.current.systemVersion.split(separator: ".").prefix(2).joined(separator: ".")
        config.applicationNameForUserAgent = "Version/\(v.contains(".") ? v : v + ".0") Mobile/15E148 Safari/604.1"
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

    /// (Re)installs page scripts and the ad rule list; the YouTube script needs to know if ad blocking is on.
    private func applyContent(reload: Bool) {
        var controllers = tabs.map { $0.webView.configuration.userContentController }
        if let c = config?.userContentController { controllers.append(c) }
        let yt = "(P => {\n" + youtubeJS + "\n})({\"adblock\": \(adblock)});"
        for c in controllers {
            c.removeAllUserScripts()
            if !spoofJS.isEmpty {
                c.addUserScript(WKUserScript(source: spoofJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            }
            c.addUserScript(WKUserScript(source: yt, injectionTime: .atDocumentStart, forMainFrameOnly: false))
            c.removeAllContentRuleLists()
            if adblock, let adRules { c.add(adRules) }
        }
        if reload { current?.webView.reload() }
    }

    /// iOS pauses page video when the app leaves the screen; youtube.js undoes that for YouTube.
    func setBackground(_ on: Bool) {
        for t in tabs { t.webView.evaluateJavaScript("window.__pbBg && __pbBg(\(on))", completionHandler: nil) }
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        browser?.history.record(url: webView.url, title: webView.title ?? "")
    }

    // By default links never go to other apps (X, YouTube…): those run outside the proxy with the real IP.
    // "Allow Opening Apps" in the menu turns that off.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let allowApps = browser?.allowApps ?? false
        let url = navigationAction.request.url
        let scheme = url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
            // tel:, mailto:, twitter://… only open on a tap, so a page can't launch apps on its own.
            if allowApps, navigationAction.navigationType == .linkActivated, let url { UIApplication.shared.open(url) }
            return decisionHandler(.cancel)
        }
        if allowApps { return decisionHandler(.allow) } // iOS may hand universal links (x.com…) to their app
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

    // Our own long-press menu: iOS's default one can hand the link to Safari or another app (outside the proxy).
    // shortcut: plain images (no link) get no menu, so no "Save Image"; add it if missed.
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping @MainActor @Sendable (UIContextMenuConfiguration?) -> Void) {
        guard let url = elementInfo.linkURL else { return completionHandler(nil) }
        let allowApps = browser?.allowApps ?? false
        completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            var items = [
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                    self?.browser?.newTab(url.absoluteString) // goes through the same app-link blocking as any load
                },
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.url = url
                },
            ]
            if allowApps {
                items.append(UIAction(title: "Open in App", image: UIImage(systemName: "arrow.up.forward.app")) { _ in
                    UIApplication.shared.open(url)
                })
            }
            return UIMenu(title: url.absoluteString, children: items)
        })
    }

    func webViewDidClose(_ webView: WKWebView) {
        browser?.close(self)
    }
}
