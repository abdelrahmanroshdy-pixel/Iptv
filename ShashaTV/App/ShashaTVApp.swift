import SwiftUI
import AVFoundation

@main
struct ShashaTVApp: App {
    @StateObject private var app = AppState()

    init() {
        // Play sound even when the silent switch is on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        _ = NetworkMonitor.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.library)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        if app.account == nil {
            LoginView()
        } else {
            MainTabView()
        }
    }
}
