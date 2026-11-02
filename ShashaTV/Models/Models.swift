import Foundation
import SwiftUI

enum MediaKind: String, Codable, Hashable, CaseIterable {
    case live, movie, series, episode

    var title: LocalizedStringKey {
        switch self {
        case .live: return "Live TV"
        case .movie: return "Movies"
        case .series: return "Series"
        case .episode: return "Episodes"
        }
    }
}

struct MediaCategory: Identifiable, Hashable, Codable {
    let id: String
    let name: String
}

struct MediaItem: Identifiable, Hashable, Codable {
    var id: String
    var kind: MediaKind
    var name: String
    var imageURL: URL?
    var categoryId: String?
    var containerExtension: String?
    /// Full stream URL (used by M3U playlists).
    var directURL: URL?
    var rating: String?
    var plot: String?
    var year: String?
    var parentName: String?
    var seasonNumber: Int?
    var episodeNumber: Int?

    /// Unique across kinds (a channel and a movie may share the same numeric id).
    var key: String { "\(kind.rawValue):\(id)" }

    var displayTitle: String {
        guard kind == .episode, let parentName else { return name }
        if let s = seasonNumber, let e = episodeNumber { return "\(parentName) · S\(s)E\(e)" }
        return "\(parentName) · \(name)"
    }

    /// Xtream series open a seasons page; everything else plays directly.
    var opensDetail: Bool { kind == .series && directURL == nil }
}

struct Season: Identifiable, Hashable {
    let number: Int
    var episodes: [MediaItem]
    var id: Int { number }
}

struct SeriesDetail {
    var plot: String?
    var cover: URL?
    var seasons: [Season]
}

struct AccountInfo {
    var status: String?
    var expiry: Date?
    var maxConnections: String?
    var activeConnections: String?
}

struct PlaybackRequest: Identifiable {
    let id = UUID()
    let item: MediaItem
    let url: URL
}

struct PlaybackProgress: Codable, Hashable {
    var item: MediaItem
    var position: Double
    var duration: Double
    var updated: Date

    var fraction: Double { duration > 0 ? min(1, position / duration) : 0 }
    var isFinished: Bool { duration > 0 && position / duration > 0.95 }
}

struct XtreamCredentials: Codable, Hashable {
    var server: String
    var username: String
    var password: String

    /// Accepts "host:port", "http://host:port/", ".../player_api.php" etc.
    static func normalizeServer(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "http://" + s }
        guard var comps = URLComponents(string: s), let host = comps.host, !host.isEmpty else { return nil }
        var path = comps.path
        for suffix in ["/player_api.php", "/get.php", "/xmltv.php"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        comps.path = path
        comps.query = nil
        comps.fragment = nil
        return comps.string
    }
}

enum Account: Codable, Hashable {
    case xtream(XtreamCredentials)
    case m3u(URL)

    private var identity: String {
        switch self {
        case .xtream(let c): return "x|\(c.server)|\(c.username)"
        case .m3u(let u): return "m|\(u.absoluteString)"
        }
    }

    /// Stable id used to separate caches / favorites per account.
    var namespace: String { String(Hashing.sha256(identity).prefix(16)) }

    var serverDisplay: String {
        switch self {
        case .xtream(let c): return c.server
        case .m3u(let u): return u.host ?? u.absoluteString
        }
    }

    var usernameDisplay: String? {
        if case .xtream(let c) = self { return c.username }
        return nil
    }

    /// Builds an account from a playlist link. Links of the form
    /// `http://host:port/get.php?username=..&password=..` are turned into an
    /// Xtream account, which loads one category at a time (much less data).
    static func fromPlaylistLink(_ raw: String) throws -> Account {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw AppError.invalidPlaylist }
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "http://" + s }
        guard let url = URL.lenient(s), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              comps.host != nil else { throw AppError.invalidPlaylist }
        let items = comps.queryItems ?? []
        if comps.path.hasSuffix("get.php"),
           let user = items.first(where: { $0.name == "username" })?.value, !user.isEmpty,
           let pass = items.first(where: { $0.name == "password" })?.value, !pass.isEmpty,
           let server = XtreamCredentials.normalizeServer(url.absoluteString) {
            return .xtream(XtreamCredentials(server: server, username: user, password: pass))
        }
        return .m3u(url)
    }
}

enum AppError: LocalizedError {
    case invalidServer, invalidPlaylist, loginFailed, accountInactive(String), http(Int), emptyPlaylist, notSupported

    var errorDescription: String? {
        switch self {
        case .invalidServer: return String(localized: "The server address is not valid.")
        case .invalidPlaylist: return String(localized: "The playlist link is not valid.")
        case .loginFailed: return String(localized: "Sign in failed. Check the server, username and password.")
        case .accountInactive(let s): return String(localized: "Your subscription is not active (\(s)).")
        case .http(let code): return String(localized: "Server error (\(code)).")
        case .emptyPlaylist: return String(localized: "The playlist is empty or could not be read.")
        case .notSupported: return String(localized: "Not supported for this account type.")
        }
    }
}

func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let e = error as? URLError, e.code == .cancelled { return true }
    return false
}
