import SwiftUI
import WebKit

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ContentView: View {
    enum Sheet: String, Identifiable {
        case settings, tabs
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
        .sheet(item: $sheet) { s in
            switch s {
            case .settings: SettingsView { Task { await browser.connect() } }
            case .tabs: TabsView(browser: browser)
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
            Text("US Browser").font(.largeTitle.bold())
            Text(browser.status)
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if browser.connecting {
                ProgressView()
            } else {
                Button("Reconnect") { Task { await browser.connect() } }
                    .buttonStyle(.borderedProminent)
                Button("Proxy Settings") { sheet = .settings }
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
    @FocusState private var editing: Bool

    private var host: String { tab.url?.host() ?? "" }

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
            }
            if !editing { bottomBar }
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
                Button("Check My IP", systemImage: "network") { tab.go("https://browserleaks.com/ip") }
                Divider()
                Button("Proxy Settings", systemImage: "gearshape") { sheet = .settings }
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

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var s = ProxySettings.load()
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $s.type) {
                    Text("SOCKS5").tag("socks5")
                    Text("HTTP").tag("http")
                }
                TextField("Host", text: $s.host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Port", value: $s.port, format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                TextField("Username (optional)", text: $s.user)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password (optional)", text: $s.pass)
                Section {
                    Text("Location and timezone are taken from the proxy IP automatically. A US residential proxy works best.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Proxy")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Connect") { s.save(); onSave(); dismiss() }
                }
            }
        }
    }
}
