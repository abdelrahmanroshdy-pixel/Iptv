import Foundation
import SwiftUI
import CoreGraphics

enum VideoQuality: String, CaseIterable, Identifiable {
    case saver, balanced, high

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .saver: return "Data saver"
        case .balanced: return "Balanced"
        case .high: return "Best quality"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .saver: return "Up to 360p, about 0.3 GB per hour."
        case .balanced: return "Up to 720p, about 0.8 GB per hour."
        case .high: return "No limit. Uses the most data."
        }
    }

    /// 0 = no limit. Only effective when the stream offers several qualities (HLS).
    var peakBitRate: Double {
        switch self {
        case .saver: return 700_000
        case .balanced: return 1_800_000
        case .high: return 0
        }
    }

    var maxResolution: CGSize {
        switch self {
        case .saver: return CGSize(width: 640, height: 360)
        case .balanced: return CGSize(width: 1280, height: 720)
        case .high: return .zero
        }
    }

    /// How far ahead the player downloads. Smaller = less wasted data when you
    /// stop watching early. 0 = let iOS decide.
    var forwardBuffer: TimeInterval {
        switch self {
        case .saver: return 8
        case .balanced: return 20
        case .high: return 0
        }
    }
}

enum PosterMode: String, CaseIterable, Identifiable {
    case always, wifiOnly, never

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .always: return "Always"
        case .wifiOnly: return "Wi-Fi only"
        case .never: return "Never"
        }
    }
}

enum Prefs {
    enum Key {
        static let quality = "videoQuality"
        static let posters = "posterMode"
        static let cacheHours = "cacheHours"
    }

    static var quality: VideoQuality {
        VideoQuality(rawValue: UserDefaults.standard.string(forKey: Key.quality) ?? "") ?? .balanced
    }

    static var posterMode: PosterMode {
        PosterMode(rawValue: UserDefaults.standard.string(forKey: Key.posters) ?? "") ?? .always
    }

    static var cacheMaxAge: TimeInterval {
        let h = UserDefaults.standard.integer(forKey: Key.cacheHours)
        return TimeInterval((h > 0 ? h : 24) * 3600)
    }
}
