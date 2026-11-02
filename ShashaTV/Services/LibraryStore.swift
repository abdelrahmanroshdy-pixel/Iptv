import Foundation

/// Favorites and "continue watching", saved per account on the device.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [MediaItem] = []
    @Published private(set) var progress: [String: PlaybackProgress] = [:]

    private var fileURL: URL?

    private struct Snapshot: Codable {
        var favorites: [MediaItem]
        var progress: [String: PlaybackProgress]
    }

    func load(namespace: String?) {
        guard let namespace else {
            fileURL = nil
            favorites = []
            progress = [:]
            return
        }
        let url = Storage.libraryRoot.appendingPathComponent("\(namespace).json")
        fileURL = url
        if let data = try? Data(contentsOf: url),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            favorites = snap.favorites
            progress = snap.progress
        } else {
            favorites = []
            progress = [:]
        }
    }

    func isFavorite(_ item: MediaItem) -> Bool {
        favorites.contains { $0.key == item.key }
    }

    func toggleFavorite(_ item: MediaItem) {
        if let i = favorites.firstIndex(where: { $0.key == item.key }) {
            favorites.remove(at: i)
        } else {
            favorites.insert(item, at: 0)
        }
        persist()
    }

    func progress(for item: MediaItem) -> PlaybackProgress? {
        progress[item.key]
    }

    func saveProgress(_ item: MediaItem, position: Double, duration: Double) {
        guard item.kind != .live, position.isFinite, duration.isFinite, duration > 0 else { return }
        progress[item.key] = PlaybackProgress(item: item, position: position, duration: duration, updated: Date())
        // Keep the file small.
        if progress.count > 300 {
            let oldest = progress.values.sorted { $0.updated < $1.updated }.prefix(progress.count - 300)
            for p in oldest { progress[p.item.key] = nil }
        }
        persist()
    }

    func removeProgress(_ item: MediaItem) {
        progress[item.key] = nil
        persist()
    }

    var continueWatching: [PlaybackProgress] {
        Array(progress.values
            .filter { !$0.isFinished && $0.position > 30 }
            .sorted { $0.updated > $1.updated }
            .prefix(20))
    }

    private func persist() {
        guard let fileURL else { return }
        let snap = Snapshot(favorites: favorites, progress: progress)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
