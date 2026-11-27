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
        var c = type == "http" ? ProxyConfiguration(httpCONNECTProxy: ep) : ProxyConfiguration(socksv5Proxy: ep)
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
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var webView: WKWebView?
    @Published var status = "Not connected"
    @Published var address = ""
    @Published var error = ""

    /// Fail closed: no webview exists until the proxy is verified, so the real IP is never used.
    func connect() async {
        webView = nil
        guard let proxy = ProxySettings.load().configuration() else {
            status = "No proxy set — tap ⚙️"
            return
        }
        status = "Checking proxy…"
        do {
            let geo = try await Geo.lookup(via: proxy)
            guard let c = geo.coords, TimeZone(identifier: geo.timezone) != nil else {
                throw BrowserError(errorDescription: "Could not read the proxy location")
            }
            webView = try makeWebView(proxy: proxy, lat: c.0, lon: c.1, tz: geo.timezone)
            status = "\(geo.country == "US" ? "🇺🇸" : "⚠️ \(geo.country)") \(geo.city), \(geo.region) · \(geo.ip) · \(geo.timezone)"
            go(address.isEmpty ? "https://browserleaks.com/ip" : address)
        } catch {
            status = "Proxy error: \(error.localizedDescription)"
        }
    }

    private func makeWebView(proxy: ProxyConfiguration, lat: Double, lon: Double, tz: String) throws -> WKWebView {
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
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }

    func go(_ input: String) {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let wv = webView else { return }
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
        wv.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        address = webView.url?.absoluteString ?? address
        error = ""
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    private func report(_ e: Error) {
        guard (e as NSError).code != NSURLErrorCancelled else { return } // a newer navigation replaced this one
        error = "⚠️ " + e.localizedDescription
    }

    // target="_blank" links open in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }
}
