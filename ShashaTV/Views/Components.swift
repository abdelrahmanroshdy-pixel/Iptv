import SwiftUI

struct PosterImage: View {
    let url: URL?
    var maxPixel: CGFloat = 300
    var fit = false
    var placeholder = "film"

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            } else {
                Color(uiColor: .secondarySystemBackground)
                Image(systemName: placeholder)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await ImagePipeline.shared.image(for: url, maxPixel: maxPixel)
        }
    }
}

struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.black.opacity(0.4))
                Rectangle().fill(Color.accentColor).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 3)
    }
}

struct PosterTile: View {
    let item: MediaItem
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay { PosterImage(url: item.imageURL, maxPixel: 320, placeholder: item.kind == .series ? "rectangle.stack" : "film") }
                .overlay(alignment: .bottom) {
                    if let p = library.progress(for: item), !p.isFinished, p.position > 30 {
                        ProgressLine(fraction: p.fraction)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if library.isFavorite(item) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
        }
    }
}

struct ChannelRow: View {
    let item: MediaItem
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: item.imageURL, maxPixel: 120, fit: true, placeholder: "tv")
                .frame(width: 56, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(item.name)
                .lineLimit(2)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            if library.isFavorite(item) {
                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
            }
        }
        .contentShape(Rectangle())
    }
}

struct MessageView: View {
    let systemImage: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FavoriteButton: View {
    let item: MediaItem
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        let fav = library.isFavorite(item)
        Button {
            library.toggleFavorite(item)
        } label: {
            if fav {
                Label("Remove from favorites", systemImage: "heart.slash")
            } else {
                Label("Add to favorites", systemImage: "heart")
            }
        }
    }
}
