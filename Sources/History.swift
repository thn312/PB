import Foundation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var url: String
    var title: String
    var date: Date
}

/// Browsing history, newest first, kept only on this device (Application Support/history.json).
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    private let limit = 2000
    private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("history.json")

    init() {
        entries = (try? JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: file))) ?? []
    }

    func record(url: URL?, title: String) {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let u = url.absoluteString
        if let first = entries.first, first.url == u { // reload or same page again: refresh instead of duplicating
            if !title.isEmpty { entries[0].title = title }
            entries[0].date = Date()
        } else {
            entries.insert(HistoryEntry(url: u, title: title, date: Date()), at: 0)
            if entries.count > limit { entries.removeLast(entries.count - limit) }
        }
        save()
    }

    func delete(_ e: HistoryEntry) { entries.removeAll { $0.id == e.id }; save() }

    func clear() { entries = []; save() }

    /// Most recent distinct pages whose URL or title contains `query`.
    func matches(_ query: String, limit: Int = 4) -> [HistoryEntry] {
        let q = query.lowercased()
        var seen = Set<String>()
        var out: [HistoryEntry] = []
        for e in entries where out.count < limit {
            if (e.url.lowercased().contains(q) || e.title.lowercased().contains(q)) && seen.insert(e.url).inserted {
                out.append(e)
            }
        }
        return out
    }

    private func save() {
        // shortcut: rewrites the whole file per page load (≤2000 entries, a few hundred KB); batch writes if it ever feels slow.
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }
}

enum Suggest {
    /// Google's search suggestions. `session` goes through the active proxy, so typing never leaks the real IP.
    static func google(_ query: String, session: URLSession) async -> [String] {
        var c = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
        c.queryItems = [
            URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "ie", value: "utf-8"), URLQueryItem(name: "oe", value: "utf-8"),
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = c.url, let r = try? await session.data(from: url) else { return [] }
        return parse(r.0)
    }

    /// Response looks like ["query", ["s1", "s2", ...], ...].
    static func parse(_ data: Data) -> [String] {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any], arr.count > 1,
              let list = arr[1] as? [String] else { return [] }
        return Array(list.prefix(6))
    }
}
