import SwiftUI
import WebKit

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ContentView: View {
    enum Sheet: String, Identifiable {
        case settings, tabs, history
        var id: String { rawValue }
    }

    @StateObject private var browser = Browser()
    @State private var sheet: Sheet?

    var body: some View {
        Group {
            if let tab = browser.current {
                // .id resets the address bar state when switching tabs.
                BrowserScreen(browser: browser, tab: tab, sheet: $sheet).id(tab.id)
            } else {
                ConnectScreen(browser: browser, sheet: $sheet)
            }
        }
        .tint(.orange)
        .task { await browser.connect() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            browser.setBackground(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            browser.setBackground(false)
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .settings: ProxyListView(browser: browser)
            case .tabs: TabsView(browser: browser)
            case .history: HistoryView(browser: browser, history: browser.history)
            }
        }
    }
}

struct ConnectScreen: View {
    @ObservedObject var browser: Browser
    @Binding var sheet: ContentView.Sheet?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 64)).foregroundStyle(.orange)
            Text("PB").font(.largeTitle.bold())
            Text(browser.status)
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if browser.connecting {
                ProgressView()
            } else {
                Button("Reconnect") { Task { await browser.connect() } }
                    .buttonStyle(.borderedProminent)
                Button("Proxies") { sheet = .settings }
            }
        }
        .padding(32)
    }
}

struct BrowserScreen: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    @Binding var sheet: ContentView.Sheet?
    @State private var text = ""
    @State private var suggestions: [String] = []
    @FocusState private var editing: Bool

    private var host: String { tab.url?.host() ?? "" }
    /// Typing something new (not just the selected current URL).
    private var typing: Bool { editing && !text.isEmpty && text != tab.url?.absoluteString }

    private func open(_ input: String) {
        tab.go(input)
        editing = false
    }

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ZStack(alignment: .top) {
                WebViewHost(webView: tab.webView)
                if !tab.error.isEmpty {
                    Text(tab.error)
                        .font(.caption).foregroundStyle(.white)
                        .padding(10).frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.9))
                        .onTapGesture { tab.error = "" }
                        .accessibilityHint("Tap to dismiss")
                }
                if typing { suggestionList }
            }
            if !editing { bottomBar }
        }
        .task(id: typing ? text : "") {
            guard typing else { suggestions = []; return }
            try? await Task.sleep(for: .milliseconds(200)) // wait until the user pauses typing
            guard !Task.isCancelled, let session = browser.session else { return }
            let result = await Suggest.google(text, session: session)
            if !Task.isCancelled { suggestions = result }
        }
        .onAppear { text = host }
        .onChange(of: tab.url) { _, _ in if !editing { text = host } }
        .onChange(of: editing) { _, on in
            text = on ? (tab.url?.absoluteString ?? "") : host
            // Like Chrome/Safari: tapping the bar selects the URL so typing replaces it.
            if on {
                DispatchQueue.main.async {
                    UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    private var addressBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { browser.adblock.toggle() } label: {
                    Image(systemName: browser.adblock ? "shield.lefthalf.filled" : "shield.slash")
                        .font(.title3)
                        .foregroundStyle(browser.adblock ? Color.orange : Color.secondary)
                }
                .accessibilityLabel(browser.adblock ? "Ad blocking on" : "Ad blocking off")

                HStack(spacing: 6) {
                    if !editing {
                        Image(systemName: tab.url?.scheme == "https" ? "lock.fill" : "globe")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField("Search or enter address", text: $text)
                        .focused($editing)
                        .keyboardType(.webSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .multilineTextAlignment(editing ? .leading : .center)
                        .onSubmit { tab.go(text); editing = false }
                    if editing {
                        if !text.isEmpty {
                            Button { text = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Clear")
                        }
                    } else {
                        Button {
                            if tab.isLoading { tab.webView.stopLoading() } else { tab.webView.reload() }
                        } label: {
                            Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                        }
                        .accessibilityLabel(tab.isLoading ? "Stop" : "Reload")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color(.secondarySystemBackground), in: Capsule())

                if editing {
                    Button("Cancel") { editing = false }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Text(browser.status)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .padding(.bottom, 4)
            ProgressView(value: tab.progress)
                .progressViewStyle(.linear)
                .opacity(tab.isLoading ? 1 : 0)
        }
        .background(.bar)
    }

    private var suggestionList: some View {
        List {
            let visited = browser.history.matches(text)
            if !visited.isEmpty {
                Section("History") {
                    ForEach(visited) { e in
                        Button { open(e.url) } label: {
                            suggestionRow("clock", e.title.isEmpty ? e.url : e.title, detail: e.url)
                        }
                    }
                }
            }
            Section("Search") {
                Button { open(text) } label: { suggestionRow("magnifyingglass", text) }
                ForEach(suggestions.filter { $0 != text }, id: \.self) { s in
                    Button { open(s) } label: { suggestionRow("magnifyingglass", s) }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(.systemBackground))
    }

    private func suggestionRow(_ icon: String, _ title: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1).foregroundStyle(.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            barButton("chevron.backward", "Back", enabled: tab.canGoBack) { tab.webView.goBack() }
            barButton("chevron.forward", "Forward", enabled: tab.canGoForward) { tab.webView.goForward() }
            Group {
                if let url = tab.url {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                } else {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Share")
            Button { sheet = .tabs } label: {
                Text("\(browser.tabs.count)")
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 1.8))
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(browser.tabs.count) tabs")
            Menu {
                Button("New Tab", systemImage: "plus") { browser.newTab() }
                Toggle(isOn: $browser.adblock) {
                    Label("Block Ads & Trackers", systemImage: "shield.lefthalf.filled")
                }
                Toggle(isOn: $browser.allowApps) {
                    Label("Allow Opening Apps", systemImage: "arrow.up.forward.app")
                }
                Button("History", systemImage: "clock") { sheet = .history }
                Button("Check My IP", systemImage: "network") { tab.go("https://browserleaks.com/ip") }
                Divider()
                if !browser.proxies.isEmpty {
                    Menu("Switch Proxy", systemImage: "arrow.triangle.swap") {
                        ForEach(browser.proxies) { p in
                            Button { browser.use(p) } label: {
                                if !browser.direct && p.id == browser.activeProxy?.id { Label(p.label, systemImage: "checkmark") } else { Text(p.label) }
                            }
                        }
                        Divider()
                        Button { browser.useDirect() } label: {
                            if browser.direct { Label("No Proxy (real IP)", systemImage: "checkmark") } else { Text("No Proxy (real IP)") }
                        }
                    }
                }
                Button("Proxies", systemImage: "gearshape") { sheet = .settings }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Menu")
        }
        .font(.title3)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func barButton(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .disabled(!enabled)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
    }
}

struct TabsView: View {
    @ObservedObject var browser: Browser
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(browser.tabs) { tab in
                    TabRow(tab: tab, selected: tab === browser.current) { browser.close(tab) }
                        .contentShape(Rectangle())
                        .onTapGesture { browser.current = tab; dismiss() }
                }
                .onDelete { offsets in offsets.map { browser.tabs[$0] }.forEach { browser.close($0) } }
            }
            .navigationTitle("\(browser.tabs.count) Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { browser.newTab(); dismiss() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New tab")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct TabRow: View {
    @ObservedObject var tab: Tab
    let selected: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "circle.inset.filled" : "circle")
                .foregroundStyle(selected ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title.isEmpty ? "New Tab" : tab.title).lineLimit(1)
                Text(tab.url?.host() ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark").foregroundStyle(.secondary) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close tab")
        }
        .padding(.vertical, 4)
    }
}

struct ProxyListView: View {
    @ObservedObject var browser: Browser
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ProxySettings?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { browser.useDirect(); dismiss() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: browser.direct ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(browser.direct ? Color.orange : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No Proxy").foregroundStyle(.primary)
                                Text("Real IP and location · ad blocking still on")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(browser.direct ? "No proxy, in use" : "Use no proxy")
                }
                ForEach(browser.proxies) { p in
                    let active = !browser.direct && p.id == browser.activeProxy?.id
                    HStack(spacing: 12) {
                        Button { browser.use(p); dismiss() } label: {
                            HStack(spacing: 12) {
                                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(active ? Color.orange : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.label).foregroundStyle(.primary)
                                    Text("\(p.type.uppercased()) · \(p.host):\(String(p.port))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(active ? "\(p.label), in use" : "Use \(p.label)")
                        Button { editing = p } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(p.label)")
                    }
                }
                .onDelete { browser.deleteProxies(at: $0) }
                if browser.proxies.isEmpty {
                    Text("Tap + to add a proxy.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Proxies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = ProxySettings() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add proxy")
                }
            }
            .sheet(item: $editing) { p in
                ProxyEditor(proxy: p, isNew: !browser.proxies.contains { $0.id == p.id }) { browser.saveProxy($0) }
            }
        }
    }
}

struct ProxyEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var proxy: ProxySettings
    let isNew: Bool
    let onSave: (ProxySettings) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Dallas residential)", text: $proxy.name)
                Picker("Type", selection: $proxy.type) {
                    Text("SOCKS5").tag("socks5")
                    Text("HTTP").tag("http")
                }
                TextField("Host", text: $proxy.host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Port", value: $proxy.port, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Username (optional)", text: $proxy.user)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password (optional)", text: $proxy.pass)
                Section {
                    Text("Location and timezone are taken from the proxy IP automatically. Residential proxies work best.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isNew ? "New Proxy" : "Edit Proxy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        proxy.host = proxy.host.trimmingCharacters(in: .whitespaces)
                        onSave(proxy)
                        dismiss()
                    }
                    .disabled(proxy.configuration() == nil) // empty host or bad port
                }
            }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var history: HistoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmClear = false

    struct Day: Identifiable {
        let date: Date
        let entries: [HistoryEntry]
        var id: Date { date }
    }

    /// Entries grouped by day, newest day first, filtered by the search box.
    private var days: [Day] {
        let q = query.lowercased()
        let list = q.isEmpty ? history.entries
            : history.entries.filter { $0.url.lowercased().contains(q) || $0.title.lowercased().contains(q) }
        let groups = Dictionary(grouping: list) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { Day(date: $0, entries: groups[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { day in
                    Section(day.date.formatted(date: .complete, time: .omitted)) {
                        ForEach(day.entries) { e in
                            Button {
                                browser.current?.go(e.url)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title.isEmpty ? e.url : e.title).lineLimit(1).foregroundStyle(.primary)
                                    Text(e.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .onDelete { offsets in offsets.map { day.entries[$0] }.forEach { history.delete($0) } }
                    }
                }
                if history.entries.isEmpty {
                    Text("No history yet.").foregroundStyle(.secondary)
                }
            }
            .searchable(text: $query, prompt: "Search history")
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear", role: .destructive) { confirmClear = true }
                        .disabled(history.entries.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { history.clear() }
            }
        }
    }
}
