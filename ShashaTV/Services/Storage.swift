import Foundation
import Security

/// Small on-disk cache for channel / movie lists so they are not downloaded
/// again every time the app opens.
final class CacheStore {
    let dir: URL

    init(namespace: String) {
        dir = Storage.feedsRoot.appendingPathComponent(namespace, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL {
        dir.appendingPathComponent(Hashing.sha256(key))
    }

    func read(_ key: String, maxAge: TimeInterval) -> Data? {
        let f = file(key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        if maxAge.isFinite && Date().timeIntervalSince(modified) > maxAge { return nil }
        return try? Data(contentsOf: f)
    }

    func write(_ data: Data, key: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

enum Storage {
    static var cachesRoot: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }
    static var feedsRoot: URL { cachesRoot.appendingPathComponent("feeds", isDirectory: true) }
    static var imagesRoot: URL { cachesRoot.appendingPathComponent("images", isDirectory: true) }
    static var libraryRoot: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("library", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cacheSize() -> Int64 {
        [feedsRoot, imagesRoot].reduce(0) { $0 + directorySize($1) }
    }

    static func clearCaches() {
        for dir in [feedsRoot, imagesRoot] {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// Saves the login in the iOS Keychain (encrypted), not in plain settings.
enum AccountStore {
    private static let service = "com.shasha.tv.account"
    private static let accountKey = "current"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: accountKey]
    }

    static func save(_ account: Account) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var q = baseQuery
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load() -> Account? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
