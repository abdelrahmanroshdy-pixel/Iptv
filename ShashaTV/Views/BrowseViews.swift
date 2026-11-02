import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        TabView {
            NavigationStack { CategoriesView(kind: .live) }
                .tabItem { Label("Live TV", systemImage: "tv") }
            NavigationStack { CategoriesView(kind: .movie) }
                .tabItem { Label("Movies", systemImage: "film") }
            NavigationStack { CategoriesView(kind: .series) }
                .tabItem { Label("Series", systemImage: "rectangle.stack") }
            NavigationStack { LibraryView() }
                .tabItem { Label("My List", systemImage: "heart") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(item: $app.playback) { request in
            PlayerScreen(request: request)
                .environmentObject(app)
                .environmentObject(library)
        }
    }
}

struct CategoriesView: View {
    let kind: MediaKind

    @EnvironmentObject private var app: AppState
    @State private var categories: [MediaCategory] = []
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""

    private var filtered: [MediaCategory] {
        query.isEmpty ? categories : categories.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(filtered) { category in
            NavigationLink(value: category) {
                Text(category.name)
            }
        }
        .listStyle(.plain)
        .overlay {
            if categories.isEmpty {
                if loading {
                    ProgressView()
                } else if let error {
                    MessageView(systemImage: "wifi.exclamationmark", message: error) {
                        Task { await load(refresh: true) }
                    }
                } else {
                    MessageView(systemImage: "tray", message: String(localized: "No categories found."))
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationDestination(for: MediaCategory.self) { ItemsView(kind: kind, category: $0) }
        .navigationDestination(for: MediaItem.self) { SeriesDetailView(series: $0) }
        .searchable(text: $query, prompt: Text("Search categories"))
        .refreshable { await load(refresh: true) }
        .task { if categories.isEmpty { await load(refresh: false) } }
    }

    @MainActor
    private func load(refresh: Bool) async {
        guard let provider = app.provider else { return }
        if categories.isEmpty { loading = true }
        defer { loading = false }
        do {
            categories = try await provider.categories(kind, refresh: refresh)
            error = nil
        } catch {
            if !isCancellation(error) { self.error = error.localizedDescription }
        }
    }
}

struct ItemsView: View {
    let kind: MediaKind
    let category: MediaCategory

    @EnvironmentObject private var app: AppState
    @State private var items: [MediaItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var query = ""

    private var filtered: [MediaItem] {
        query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if kind == .live {
                List(filtered, id: \.key) { item in
                    Button { app.play(item) } label: { ChannelRow(item: item) }
                        .swipeActions { FavoriteButton(item: item).tint(.pink) }
                        .contextMenu { FavoriteButton(item: item) }
                }
                .listStyle(.plain)
                .refreshable { await load(refresh: true) }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
                        ForEach(filtered, id: \.key) { item in
                            tile(item)
                        }
                    }
                    .padding()
                }
                .refreshable { await load(refresh: true) }
            }
        }
        .overlay {
            if items.isEmpty {
                if loading {
                    ProgressView()
                } else if let error {
                    MessageView(systemImage: "wifi.exclamationmark", message: error) {
                        Task { await load(refresh: true) }
                    }
                } else {
                    MessageView(systemImage: "tray", message: String(localized: "Nothing in this category."))
                }
            }
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Search"))
        .task { if items.isEmpty { await load(refresh: false) } }
    }

    @ViewBuilder
    private func tile(_ item: MediaItem) -> some View {
        if item.opensDetail {
            NavigationLink(value: item) { PosterTile(item: item) }
                .buttonStyle(.plain)
                .contextMenu { FavoriteButton(item: item) }
        } else {
            Button { app.play(item) } label: { PosterTile(item: item) }
                .buttonStyle(.plain)
                .contextMenu { FavoriteButton(item: item) }
        }
    }

    @MainActor
    private func load(refresh: Bool) async {
        guard let provider = app.provider else { return }
        if items.isEmpty { loading = true }
        defer { loading = false }
        do {
            items = try await provider.items(kind, categoryId: category.id, refresh: refresh)
            error = nil
        } catch {
            if !isCancellation(error) { self.error = error.localizedDescription }
        }
    }
}

struct SeriesDetailView: View {
    let series: MediaItem

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @State private var detail: SeriesDetail?
    @State private var season = 0
    @State private var error: String?

    private var episodes: [MediaItem] {
        detail?.seasons.first { $0.number == season }?.episodes ?? []
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Color.clear
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .frame(width: 110)
                        .overlay { PosterImage(url: detail?.cover ?? series.imageURL, maxPixel: 330, placeholder: "rectangle.stack") }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(series.name).font(.headline)
                        if let year = series.year { Text(year).font(.subheadline).foregroundStyle(.secondary) }
                        if let rating = series.rating, rating != "0" {
                            Label(rating, systemImage: "star.fill").font(.subheadline).foregroundStyle(.orange)
                        }
                        if let plot = detail?.plot ?? series.plot {
                            Text(plot).font(.footnote).foregroundStyle(.secondary).lineLimit(8)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }

            if let detail {
                if detail.seasons.count > 1 {
                    Section {
                        Picker("Season", selection: $season) {
                            ForEach(detail.seasons) { s in
                                Text("Season \(s.number)").tag(s.number)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Section {
                    ForEach(episodes, id: \.key) { ep in
                        Button { app.play(ep) } label: { episodeRow(ep) }
                    }
                } header: {
                    if detail.seasons.count == 1 { Text("Season \(season)") }
                }
            } else if let error {
                MessageView(systemImage: "wifi.exclamationmark", message: error) {
                    Task { await load(refresh: true) }
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationTitle(series.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    library.toggleFavorite(series)
                } label: {
                    Image(systemName: library.isFavorite(series) ? "heart.fill" : "heart")
                }
            }
        }
        .refreshable { await load(refresh: true) }
        .task { if detail == nil { await load(refresh: false) } }
    }

    private func episodeRow(_ ep: MediaItem) -> some View {
        let p = library.progress(for: ep)
        return HStack(spacing: 12) {
            Text("\(ep.episodeNumber ?? 0)")
                .font(.headline.monospacedDigit())
                .frame(width: 30)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(ep.name).lineLimit(2).foregroundStyle(.primary)
                if let p, !p.isFinished, p.position > 30 {
                    ProgressView(value: p.fraction).tint(.accentColor)
                }
            }
            Spacer(minLength: 0)
            if p?.isFinished == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "play.circle").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }

    @MainActor
    private func load(refresh: Bool) async {
        guard let provider = app.provider else { return }
        do {
            let d = try await provider.seriesDetail(series, refresh: refresh)
            detail = d
            error = nil
            if !d.seasons.contains(where: { $0.number == season }) {
                season = d.seasons.first?.number ?? 0
            }
        } catch {
            if !isCancellation(error) { self.error = error.localizedDescription }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        let continuing = library.continueWatching
        let live = library.favorites.filter { $0.kind == .live }
        let movies = library.favorites.filter { $0.kind == .movie }
        let series = library.favorites.filter { $0.kind == .series || $0.kind == .episode }

        List {
            if !continuing.isEmpty {
                Section("Continue watching") {
                    ForEach(continuing, id: \.item.key) { p in
                        Button { app.play(p.item) } label: {
                            HStack(spacing: 12) {
                                PosterImage(url: p.item.imageURL, maxPixel: 160)
                                    .frame(width: 48, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(p.item.displayTitle).lineLimit(2).foregroundStyle(.primary)
                                    ProgressView(value: p.fraction).tint(.accentColor)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { library.removeProgress(p.item) } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            if !live.isEmpty {
                Section("Channels") {
                    ForEach(live, id: \.key) { item in
                        Button { app.play(item) } label: { ChannelRow(item: item) }
                            .swipeActions { FavoriteButton(item: item).tint(.pink) }
                    }
                }
            }
            if !movies.isEmpty {
                Section("Movies") {
                    ForEach(movies, id: \.key) { item in
                        Button { app.play(item) } label: { ChannelRow(item: item) }
                            .swipeActions { FavoriteButton(item: item).tint(.pink) }
                    }
                }
            }
            if !series.isEmpty {
                Section("Series") {
                    ForEach(series, id: \.key) { item in
                        Group {
                            if item.opensDetail {
                                NavigationLink(value: item) { ChannelRow(item: item) }
                            } else {
                                Button { app.play(item) } label: { ChannelRow(item: item) }
                            }
                        }
                        .swipeActions { FavoriteButton(item: item).tint(.pink) }
                    }
                }
            }
        }
        .overlay {
            if continuing.isEmpty && library.favorites.isEmpty {
                MessageView(systemImage: "heart",
                            message: String(localized: "Nothing here yet. Long-press any channel, movie or series to add it to your favorites."))
            }
        }
        .navigationTitle("My List")
        .navigationDestination(for: MediaItem.self) { SeriesDetailView(series: $0) }
    }
}
