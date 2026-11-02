import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var accountInfo: AccountInfo?
    @Published var playback: PlaybackRequest?

    private(set) var provider: (any ContentProvider)?
    let library = LibraryStore()

    init() {
        if let saved = AccountStore.load() {
            activate(saved, provider: Self.makeProvider(saved))
        }
    }

    static func makeProvider(_ account: Account) -> any ContentProvider {
        let cache = CacheStore(namespace: account.namespace)
        switch account {
        case .xtream(let creds): return XtreamProvider(creds: creds, cache: cache)
        case .m3u(let url): return M3UProvider(url: url, cache: cache)
        }
    }

    func login(_ account: Account) async throws {
        let provider = Self.makeProvider(account)
        let info = try await provider.validate()
        AccountStore.save(account)
        activate(account, provider: provider)
        accountInfo = info
    }

    func refreshAccountInfo() async {
        guard let provider, case .xtream = account else { return }
        if let info = try? await provider.validate() { accountInfo = info }
    }

    func logout() {
        provider?.clearCache()
        AccountStore.delete()
        provider = nil
        accountInfo = nil
        playback = nil
        library.load(namespace: nil)
        account = nil
    }

    func play(_ item: MediaItem) {
        guard let url = provider?.streamURL(for: item) else { return }
        playback = PlaybackRequest(item: item, url: url)
    }

    private func activate(_ account: Account, provider: any ContentProvider) {
        self.provider = provider
        library.load(namespace: account.namespace)
        self.account = account
    }
}
