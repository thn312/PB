import SwiftUI

@main
struct USBrowserApp: App {
    init() {
        // Makes WKWebView send Accept-Language: en-US (applies fully from the 2nd launch).
        UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
