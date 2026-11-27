import SwiftUI
import WebKit

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var browser = Browser()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { browser.webView?.goBack() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back")
                TextField("Search or enter address", text: $browser.address)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { browser.go(browser.address) }
                Button { browser.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Reload")
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Proxy settings")
            }
            .padding(8)
            Text(browser.status)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).padding(.bottom, 4)
            if let wv = browser.webView {
                WebViewHost(webView: wv).id(ObjectIdentifier(wv))
            } else {
                Spacer()
                Button("Reconnect") { Task { await browser.connect() } }
                Spacer()
            }
        }
        .task { await browser.connect() }
        .sheet(isPresented: $showSettings) {
            SettingsView { Task { await browser.connect() } }
        }
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
