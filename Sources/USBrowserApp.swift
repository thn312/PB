import AVFoundation
import SwiftUI

@main
struct USBrowserApp: App {
    init() {
        // Makes WKWebView send Accept-Language: en-US (applies fully from the 2nd launch).
        UserDefaults.standard.set(["en-US"], forKey: "AppleLanguages")
        // Keep page audio (YouTube music) playing with the screen off, like a music app.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
