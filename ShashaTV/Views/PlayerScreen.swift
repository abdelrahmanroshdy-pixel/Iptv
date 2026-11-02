import SwiftUI
import AVKit

struct PlayerScreen: View {
    let request: PlaybackRequest

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @StateObject private var model = PlayerModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerControllerView(player: model.player)
                .ignoresSafeArea()
            if let message = model.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    HStack {
                        Button("Try again") { model.retry() }
                            .buttonStyle(.borderedProminent)
                        Button("Close") { close() }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                }
                .padding(24)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
        .overlay(alignment: .topLeading) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(.leading, 12)
            .padding(.top, 8)
            .accessibilityLabel(Text("Close"))
        }
        .statusBarHidden()
        .onAppear { model.start(request, library: library) }
        .onDisappear { model.stop() }
    }

    private func close() {
        model.stop()
        app.playback = nil
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    let player = AVPlayer()
    @Published var errorMessage: String?

    private var request: PlaybackRequest?
    private weak var library: LibraryStore?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var didResume = false
    private var stopped = false

    func start(_ request: PlaybackRequest, library: LibraryStore) {
        guard self.request == nil else { return }
        self.request = request
        self.library = library
        load()
    }

    func retry() {
        errorMessage = nil
        load()
    }

    private func load() {
        guard let request else { return }
        stopped = false
        let quality = Prefs.quality
        let item = AVPlayerItem(url: request.url)
        // Data saving: cap bitrate/resolution and don't buffer far ahead.
        item.preferredPeakBitRate = quality.peakBitRate
        item.preferredMaximumResolution = quality.maxResolution
        item.preferredForwardBufferDuration = quality.forwardBuffer

        let isLive = request.item.kind == .live
        var resumeAt: Double?
        if !isLive, let p = library?.progress(for: request.item), !p.isFinished, p.position > 10 {
            resumeAt = max(0, p.position - 3)
        }

        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let detail = item.error?.localizedDescription
            Task { @MainActor in self?.handle(status: status, detail: detail, resumeAt: resumeAt) }
        }

        if !isLive && timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1),
                                                          queue: .main) { [weak self] _ in
                Task { @MainActor in self?.saveProgress() }
            }
        }

        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func handle(status: AVPlayerItem.Status, detail: String?, resumeAt: Double?) {
        switch status {
        case .readyToPlay:
            if let resumeAt, !didResume {
                didResume = true
                player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600))
            }
        case .failed:
            var msg = String(localized: "This stream can't be played right now. It may be offline, or its format (for example MKV) is not supported by the iPhone player.")
            if let detail { msg += "\n\n" + detail }
            errorMessage = msg
        default:
            break
        }
    }

    private func saveProgress() {
        guard let request, let item = player.currentItem else { return }
        let position = player.currentTime().seconds
        let duration = item.duration.seconds
        guard position.isFinite, duration.isFinite, duration > 0, position > 0 else { return }
        library?.saveProgress(request.item, position: position, duration: duration)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        saveProgress()
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        // Releasing the item stops all downloading immediately.
        player.replaceCurrentItem(with: nil)
    }
}

struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.videoGravity = .resizeAspect
        vc.allowsPictureInPicturePlayback = false
        vc.entersFullScreenWhenPlaybackBegins = false
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
