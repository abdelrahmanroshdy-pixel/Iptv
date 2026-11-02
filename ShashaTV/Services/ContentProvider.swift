import Foundation

protocol ContentProvider {
    func validate() async throws -> AccountInfo?
    /// `kind` is `.live`, `.movie` or `.series`.
    func categories(_ kind: MediaKind, refresh: Bool) async throws -> [MediaCategory]
    func items(_ kind: MediaKind, categoryId: String, refresh: Bool) async throws -> [MediaItem]
    func seriesDetail(_ series: MediaItem, refresh: Bool) async throws -> SeriesDetail
    func streamURL(for item: MediaItem) -> URL?
    func clearCache()
}

// MARK: - Xtream Codes

final class XtreamProvider: ContentProvider {
    let creds: XtreamCredentials
    private let cache: CacheStore

    init(creds: XtreamCredentials, cache: CacheStore) {
        self.creds = creds
        self.cache = cache
    }

    private func apiURL(action: String?, params: [(String, String)] = []) -> URL? {
        var s = "\(creds.server)/player_api.php?username=\(creds.username.strictlyEncoded)&password=\(creds.password.strictlyEncoded)"
        if let action { s += "&action=\(action)" }
        for (k, v) in params { s += "&\(k)=\(v.strictlyEncoded)" }
        return URL(string: s)
    }

    /// Cached GET. Falls back to old cached data when offline.
    private func load(_ action: String, params: [(String, String)] = [], refresh: Bool) async throws -> Data {
        let key = ([action] + params.map { "\($0.0)=\($0.1)" }).joined(separator: "&")
        if !refresh, let data = cache.read(key, maxAge: Prefs.cacheMaxAge) { return data }
        guard let url = apiURL(action: action, params: params) else { throw AppError.invalidServer }
        do {
            let data = try await HTTP.get(url)
            cache.write(data, key: key)
            return data
        } catch {
            if !isCancellation(error), let stale = cache.read(key, maxAge: .infinity) { return stale }
            throw error
        }
    }

    func validate() async throws -> AccountInfo? {
        guard let url = apiURL(action: nil) else { throw AppError.invalidServer }
        let data = try await HTTP.get(url)
        guard let obj = JSONValue.parse(data) as? [String: Any],
              let ui = obj["user_info"] as? [String: Any],
              JSONValue.string(ui["auth"]) == "1" else { throw AppError.loginFailed }
        let status = JSONValue.string(ui["status"])
        if let status, status.lowercased() != "active" { throw AppError.accountInactive(status) }
        var expiry: Date?
        if let e = JSONValue.string(ui["exp_date"]), let t = Double(e), t > 0 {
            expiry = Date(timeIntervalSince1970: t)
        }
        return AccountInfo(status: status,
                           expiry: expiry,
                           maxConnections: JSONValue.string(ui["max_connections"]),
                           activeConnections: JSONValue.string(ui["active_cons"]))
    }

    func categories(_ kind: MediaKind, refresh: Bool) async throws -> [MediaCategory] {
        let action: String
        switch kind {
        case .live: action = "get_live_categories"
        case .movie: action = "get_vod_categories"
        case .series: action = "get_series_categories"
        case .episode: return []
        }
        let data = try await load(action, refresh: refresh)
        let list = JSONValue.parse(data) as? [[String: Any]] ?? []
        return list.compactMap { d in
            guard let id = JSONValue.string(d["category_id"]) else { return nil }
            return MediaCategory(id: id, name: JSONValue.string(d["category_name"]) ?? id)
        }
    }

    func items(_ kind: MediaKind, categoryId: String, refresh: Bool) async throws -> [MediaItem] {
        let action: String
        switch kind {
        case .live: action = "get_live_streams"
        case .movie: action = "get_vod_streams"
        case .series: action = "get_series"
        case .episode: return []
        }
        let data = try await load(action, params: [("category_id", categoryId)], refresh: refresh)
        let list = JSONValue.parse(data) as? [[String: Any]] ?? []
        return list.compactMap { d in
            let idKey = kind == .series ? "series_id" : "stream_id"
            guard let id = JSONValue.string(d[idKey]) else { return nil }
            let image = kind == .series ? d["cover"] : d["stream_icon"]
            return MediaItem(id: id,
                             kind: kind,
                             name: JSONValue.string(d["name"]) ?? "—",
                             imageURL: URL.lenient(JSONValue.string(image)),
                             categoryId: categoryId,
                             containerExtension: JSONValue.string(d["container_extension"]),
                             rating: JSONValue.string(d["rating"]),
                             plot: JSONValue.string(d["plot"]),
                             year: JSONValue.string(d["year"]) ?? JSONValue.string(d["releaseDate"]).map { String($0.prefix(4)) })
        }
    }

    func seriesDetail(_ series: MediaItem, refresh: Bool) async throws -> SeriesDetail {
        let data = try await load("get_series_info", params: [("series_id", series.id)], refresh: refresh)
        guard let obj = JSONValue.parse(data) as? [String: Any] else { return SeriesDetail(seasons: []) }
        let info = obj["info"] as? [String: Any]

        var bySeason: [Int: [MediaItem]] = [:]
        func add(_ e: [String: Any], seasonHint: Int?) {
            guard let id = JSONValue.string(e["id"]) else { return }
            let season = JSONValue.int(e["season"]) ?? seasonHint ?? 1
            let num = JSONValue.int(e["episode_num"])
            let einfo = e["info"] as? [String: Any]
            let title = JSONValue.string(e["title"]) ?? String(localized: "Episode \(num ?? 0)")
            let ep = MediaItem(id: id,
                               kind: .episode,
                               name: title,
                               imageURL: URL.lenient(JSONValue.string(einfo?["movie_image"])) ?? series.imageURL,
                               containerExtension: JSONValue.string(e["container_extension"]),
                               plot: JSONValue.string(einfo?["plot"]),
                               parentName: series.name,
                               seasonNumber: season,
                               episodeNumber: num)
            bySeason[season, default: []].append(ep)
        }

        if let dict = obj["episodes"] as? [String: Any] {
            for (k, v) in dict {
                for e in v as? [[String: Any]] ?? [] { add(e, seasonHint: Int(k)) }
            }
        } else if let arr = obj["episodes"] as? [Any] {
            for v in arr {
                for e in v as? [[String: Any]] ?? [] { add(e, seasonHint: nil) }
            }
        }

        let seasons = bySeason.keys.sorted().map { n in
            Season(number: n, episodes: bySeason[n]!.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) })
        }
        return SeriesDetail(plot: JSONValue.string(info?["plot"]) ?? series.plot,
                            cover: URL.lenient(JSONValue.string(info?["cover"])) ?? series.imageURL,
                            seasons: seasons)
    }

    func streamURL(for item: MediaItem) -> URL? {
        if let direct = item.directURL { return direct }
        let u = creds.username.strictlyEncoded
        let p = creds.password.strictlyEncoded
        let ext = item.containerExtension ?? "mp4"
        switch item.kind {
        // HLS (.m3u8) is what the iPhone player supports natively and it is adaptive.
        case .live: return URL(string: "\(creds.server)/live/\(u)/\(p)/\(item.id).m3u8")
        case .movie: return URL(string: "\(creds.server)/movie/\(u)/\(p)/\(item.id).\(ext)")
        case .episode: return URL(string: "\(creds.server)/series/\(u)/\(p)/\(item.id).\(ext)")
        case .series: return nil
        }
    }

    func clearCache() { cache.clear() }
}

// MARK: - M3U playlist

final class M3UProvider: ContentProvider {
    struct Playlist {
        var categories: [MediaKind: [MediaCategory]] = [:]
        var items: [String: [MediaItem]] = [:]

        static func bucket(_ kind: MediaKind, _ group: String) -> String { "\(kind.rawValue)|\(group)" }
        var isEmpty: Bool { items.isEmpty }
    }

    let playlistURL: URL
    private let cache: CacheStore
    private let lock = NSLock()
    private var playlist: Playlist?

    init(url: URL, cache: CacheStore) {
        self.playlistURL = url
        self.cache = cache
    }

    private func current() -> Playlist? {
        lock.lock(); defer { lock.unlock() }
        return playlist
    }

    private func load(refresh: Bool) async throws -> Playlist {
        if !refresh, let p = current() { return p }
        let key = "playlist"
        let data: Data
        if !refresh, let cached = cache.read(key, maxAge: Prefs.cacheMaxAge) {
            data = cached
        } else {
            do {
                data = try await HTTP.get(playlistURL)
                cache.write(data, key: key)
            } catch {
                guard !isCancellation(error), let stale = cache.read(key, maxAge: .infinity) else { throw error }
                data = stale
            }
        }
        let parsed = await Task.detached(priority: .userInitiated) { M3UParser.parse(data) }.value
        guard !parsed.isEmpty else { throw AppError.emptyPlaylist }
        lock.lock(); playlist = parsed; lock.unlock()
        return parsed
    }

    func validate() async throws -> AccountInfo? {
        _ = try await load(refresh: true)
        return nil
    }

    func categories(_ kind: MediaKind, refresh: Bool) async throws -> [MediaCategory] {
        try await load(refresh: refresh).categories[kind] ?? []
    }

    func items(_ kind: MediaKind, categoryId: String, refresh: Bool) async throws -> [MediaItem] {
        try await load(refresh: refresh).items[Playlist.bucket(kind, categoryId)] ?? []
    }

    func seriesDetail(_ series: MediaItem, refresh: Bool) async throws -> SeriesDetail {
        throw AppError.notSupported
    }

    func streamURL(for item: MediaItem) -> URL? { item.directURL }

    func clearCache() {
        cache.clear()
        lock.lock(); playlist = nil; lock.unlock()
    }
}

enum M3UParser {
    private static let attributeRegex = try! NSRegularExpression(pattern: "([A-Za-z0-9_-]+)=\"([^\"]*)\"")

    static func parse(_ data: Data) -> M3UProvider.Playlist {
        let text = String(decoding: data, as: UTF8.self)
        var result = M3UProvider.Playlist()
        var seenGroups = Set<String>()

        var name: String?
        var logo: String?
        var group: String?

        text.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return }
            if line.hasPrefix("#EXTINF") {
                let attrs = attributes(line)
                name = displayName(line) ?? attrs["tvg-name"]
                logo = attrs["tvg-logo"]
                group = attrs["group-title"]
                return
            }
            if line.hasPrefix("#EXTGRP:") {
                if group == nil { group = String(line.dropFirst("#EXTGRP:".count)) }
                return
            }
            if line.hasPrefix("#") { return }
            guard let url = URL.lenient(line) else { name = nil; logo = nil; group = nil; return }

            let kind = classify(line)
            let groupName = (group?.isEmpty == false ? group! : String(localized: "Uncategorized"))
            let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
            let item = MediaItem(id: line,
                                 kind: kind,
                                 name: (name?.isEmpty == false ? name! : url.lastPathComponent),
                                 imageURL: URL.lenient(logo),
                                 categoryId: groupName,
                                 containerExtension: ext,
                                 directURL: url)
            let bucket = M3UProvider.Playlist.bucket(kind, groupName)
            if !seenGroups.contains(bucket) {
                seenGroups.insert(bucket)
                result.categories[kind, default: []].append(MediaCategory(id: groupName, name: groupName))
            }
            result.items[bucket, default: []].append(item)
            name = nil; logo = nil; group = nil
        }
        return result
    }

    static func classify(_ url: String) -> MediaKind {
        let lower = url.lowercased()
        if lower.contains("/movie/") { return .movie }
        if lower.contains("/series/") { return .series }
        let path = lower.split(separator: "?").first.map(String.init) ?? lower
        if ["mp4", "mkv", "avi", "mov", "m4v"].contains((path as NSString).pathExtension) { return .movie }
        return .live
    }

    private static func attributes(_ line: String) -> [String: String] {
        var out: [String: String] = [:]
        let ns = line as NSString
        for m in attributeRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            out[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
        }
        return out
    }

    /// Title is everything after the first comma that is not inside quotes.
    private static func displayName(_ line: String) -> String? {
        var inQuotes = false
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if c == "\"" {
                inQuotes.toggle()
            } else if c == "," && !inQuotes {
                let n = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                return n.isEmpty ? nil : n
            }
            idx = line.index(after: idx)
        }
        return nil
    }
}
