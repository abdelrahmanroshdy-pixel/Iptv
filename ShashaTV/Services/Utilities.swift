import Foundation
import CryptoKit
import Network

enum Hashing {
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum JSONValue {
    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// IPTV panels return numbers as strings, strings as numbers, nulls... accept all.
    static func string(_ v: Any?) -> String? {
        switch v {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }

    static func int(_ v: Any?) -> Int? {
        guard let s = string(v) else { return nil }
        if let i = Int(s) { return i }
        if let d = Double(s), d.isFinite, abs(d) < Double(Int.max) { return Int(d) }
        return nil
    }
}

extension CharacterSet {
    static let rfc3986Unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

extension String {
    /// Strict percent-encoding (also encodes `+`, `&`, `/`, `@`...).
    var strictlyEncoded: String { addingPercentEncoding(withAllowedCharacters: .rfc3986Unreserved) ?? self }
}

extension URL {
    static func lenient(_ raw: String?) -> URL? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let u = URL(string: s), u.scheme != nil { return u }
        if let enc = s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let u = URL(string: enc), u.scheme != nil { return u }
        return nil
    }
}

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 300
        // We keep our own on-disk cache with a configurable lifetime.
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        return URLSession(configuration: c)
    }()

    static func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppError.http(http.statusCode)
        }
        return data
    }
}

/// Tracks whether we are on cellular / Low Data Mode.
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var expensive = false
    private var constrained = false

    var isExpensive: Bool { lock.lock(); defer { lock.unlock() }; return expensive }
    var isConstrained: Bool { lock.lock(); defer { lock.unlock() }; return constrained }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.expensive = path.isExpensive
            self.constrained = path.isConstrained
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "shasha.network-monitor"))
    }
}
