import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @AppStorage(Prefs.Key.quality) private var quality: VideoQuality = .balanced
    @AppStorage(Prefs.Key.posters) private var posters: PosterMode = .always
    @AppStorage(Prefs.Key.cacheHours) private var cacheHours: Int = 24
    @State private var cacheSize: Int64 = 0
    @State private var confirmLogout = false

    var body: some View {
        Form {
            Section("Account") {
                if let account = app.account {
                    LabeledContent("Server", value: account.serverDisplay)
                    if let user = account.usernameDisplay {
                        LabeledContent("Username", value: user)
                    }
                }
                if let info = app.accountInfo {
                    if let status = info.status {
                        LabeledContent("Status", value: status)
                    }
                    if let expiry = info.expiry {
                        LabeledContent("Expires") {
                            Text(expiry, style: .date)
                        }
                    }
                    if let max = info.maxConnections {
                        LabeledContent("Connections", value: "\(info.activeConnections ?? "0") / \(max)")
                    }
                }
            }

            Section {
                Picker("Video quality", selection: $quality) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.title).tag(q)
                    }
                }
                Text(quality.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("Show posters", selection: $posters) {
                    ForEach(PosterMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                Picker("Refresh lists every", selection: $cacheHours) {
                    Text("6 hours").tag(6)
                    Text("1 day").tag(24)
                    Text("3 days").tag(72)
                    Text("1 week").tag(168)
                }
            } header: {
                Text("Data usage")
            } footer: {
                Text("Channel and movie lists are saved on the phone and only downloaded again after this time, or when you pull down to refresh. The quality limit works on streams that offer several qualities.")
            }

            Section("Storage") {
                LabeledContent("Cache size", value: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                Button("Clear cache") {
                    app.provider?.clearCache()
                    Storage.clearCaches()
                    Task { await ImagePipeline.shared.clearMemory() }
                    cacheSize = Storage.cacheSize()
                }
            }

            Section {
                Button("Sign out", role: .destructive) { confirmLogout = true }
            } footer: {
                Text("Shasha TV is only a player and does not provide any content.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { app.logout() }
        }
        .task {
            cacheSize = Storage.cacheSize()
            await app.refreshAccountInfo()
        }
    }
}
