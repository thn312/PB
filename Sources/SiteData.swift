import Foundation
import WebKit

/// Cookies and stored website data (shared by all tabs: WKWebsiteDataStore.default()).
@MainActor
enum SiteData {
    static var store: WKWebsiteDataStore { .default() }

    /// "mobile.x.com" -> "x.com".
    /// shortcut: last two labels, so "bbc.co.uk" becomes "co.uk"; use a public-suffix list if two-part TLDs matter.
    static func site(of host: String) -> String {
        host.lowercased().split(separator: ".").suffix(2).joined(separator: ".")
    }

    /// Whether a cookie/data domain (".x.com", "api.x.com", "x.com") belongs to `site`.
    static func belongs(_ domain: String, to site: String) -> Bool {
        let d = (domain.hasPrefix(".") ? String(domain.dropFirst()) : domain).lowercased()
        return d == site || d.hasSuffix("." + site)
    }

    static func cookies(for site: String) async -> [HTTPCookie] {
        await store.httpCookieStore.allCookies()
            .filter { belongs($0.domain, to: site) }
            .sorted { ($0.domain, $0.name) < ($1.domain, $1.name) }
    }

    static func delete(_ cookie: HTTPCookie) async {
        await store.httpCookieStore.deleteCookie(cookie)
    }

    /// Cookies, local storage, caches… for one site: logs you out of it.
    static func clear(site: String) async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types).filter { belongs($0.displayName, to: site) }
        await store.removeData(ofTypes: types, for: records)
        for c in await cookies(for: site) { await delete(c) } // records can miss cookies set on sibling subdomains
    }

    /// Everything for every site: logs you out everywhere. History is kept.
    static func clearAll() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    /// JSON in the Cookie-Editor / EditThisCookie format, so it can be imported into Chrome and other tools.
    static func exportJSON(_ cookies: [HTTPCookie]) -> String {
        let list: [[String: Any]] = cookies.map { c in
            var o: [String: Any] = [
                "domain": c.domain, "name": c.name, "value": c.value, "path": c.path,
                "hostOnly": !c.domain.hasPrefix("."), "httpOnly": c.isHTTPOnly, "secure": c.isSecure,
                "session": c.isSessionOnly,
                "sameSite": c.sameSitePolicy == .sameSiteStrict ? "strict" : c.sameSitePolicy == .sameSiteLax ? "lax" : "no_restriction",
            ]
            if let exp = c.expiresDate { o["expirationDate"] = exp.timeIntervalSince1970 }
            return o
        }
        let data = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
