import SwiftUI

struct LoginView: View {
    private enum Mode: Hashable { case xtream, m3u }

    @EnvironmentObject private var app: AppState
    @State private var mode: Mode = .xtream
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var playlist = ""
    @State private var busy = false
    @State private var error: String?

    private var canSubmit: Bool {
        switch mode {
        case .xtream:
            return !server.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty && !password.isEmpty
        case .m3u:
            return !playlist.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("Shasha TV")
                            .font(.title.bold())
                        Text("A simple, light IPTV player")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    Picker("Login type", selection: $mode) {
                        Text("Xtream Codes").tag(Mode.xtream)
                        Text("M3U link").tag(Mode.m3u)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)

                switch mode {
                case .xtream:
                    Section {
                        TextField("Server (http://host:port)", text: $server)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    } footer: {
                        Text("You get these details from your IPTV provider.")
                    }
                case .m3u:
                    Section {
                        TextField("Playlist link (http://...)", text: $playlist, axis: .vertical)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(1...4)
                    } footer: {
                        Text("Tip: if the link contains username and password, the app switches to Xtream mode automatically, which is faster and uses less data.")
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text("Sign in").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || !canSubmit)
                } footer: {
                    Text("This app is only a player. It does not include any channels or content. Use your own IPTV subscription.")
                        .padding(.top, 8)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let account: Account
            switch mode {
            case .xtream:
                guard let s = XtreamCredentials.normalizeServer(server) else { throw AppError.invalidServer }
                account = .xtream(XtreamCredentials(server: s,
                                                    username: username.trimmingCharacters(in: .whitespaces),
                                                    password: password))
            case .m3u:
                account = try Account.fromPlaylistLink(playlist)
            }
            try await app.login(account)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
