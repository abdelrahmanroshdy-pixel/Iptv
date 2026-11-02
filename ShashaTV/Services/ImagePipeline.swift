import UIKit
import ImageIO

/// Loads posters / logos with a memory + disk cache, shrinks them to the size
/// actually shown, and respects the "posters" data setting and iOS Low Data Mode.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        memory.countLimit = 500
        let c = URLSessionConfiguration.default
        c.urlCache = nil
        c.timeoutIntervalForRequest = 20
        c.httpMaximumConnectionsPerHost = 4
        c.allowsConstrainedNetworkAccess = false // Low Data Mode → no posters
        session = URLSession(configuration: c)
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let cached = memory.object(forKey: url as NSURL) { return cached }
        if let running = inflight[url] { return await running.value }

        let session = self.session
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            let file = Storage.imagesRoot.appendingPathComponent(Hashing.sha256(url.absoluteString))
            if let data = try? Data(contentsOf: file), let img = UIImage(data: data) { return img }
            guard Self.downloadsAllowed() else { return nil }
            guard let result = try? await session.data(from: url) else { return nil }
            let (data, response) = result
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
            guard let img = Self.downsample(data, maxPixel: maxPixel) else { return nil }
            try? FileManager.default.createDirectory(at: Storage.imagesRoot, withIntermediateDirectories: true)
            if let encoded = Self.encode(img) { try? encoded.write(to: file, options: .atomic) }
            return img
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        if let img { memory.setObject(img, forKey: url as NSURL) }
        return img
    }

    func clearMemory() {
        memory.removeAllObjects()
    }

    private static func downloadsAllowed() -> Bool {
        switch Prefs.posterMode {
        case .always: return true
        case .never: return false
        case .wifiOnly: return !NetworkMonitor.shared.isExpensive
        }
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }

    private static func encode(_ img: UIImage) -> Data? {
        let alpha = img.cgImage?.alphaInfo ?? .none
        let hasAlpha = !(alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast)
        return hasAlpha ? img.pngData() : img.jpegData(compressionQuality: 0.8)
    }
}
