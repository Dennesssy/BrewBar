import Foundation
import Security

public struct KeychainManager: Sendable {
    public static let shared = KeychainManager()

    public init() {}

    public func saveToken(_ token: String, service: String) throws {
        guard let data = token.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw BrewBarError.keychainError("Failed to save token to Keychain with status \(status)")
        }
    }

    public func retrieveToken(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw BrewBarError.keychainError("Failed to retrieve token from Keychain with status \(status)")
        }

        return String(data: data, encoding: .utf8)
    }

    public func deleteToken(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BrewBarError.keychainError("Failed to delete token from Keychain with status \(status)")
        }
    }
}

public actor LocalStorageManager {
    public static let shared = LocalStorageManager()

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func savePreferences(_ prefs: UserPreferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            userDefaults.set(data, forKey: "brewbar_user_preferences")
        }
    }

    public func loadPreferences() -> UserPreferences {
        guard let data = userDefaults.data(forKey: "brewbar_user_preferences"),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return UserPreferences()
        }
        return prefs
    }

    public func saveFavorites(_ favorites: Set<String>) {
        userDefaults.set(Array(favorites), forKey: "brewbar_favorites")
    }

    public func loadFavorites() -> Set<String> {
        if let array = userDefaults.array(forKey: "brewbar_favorites") as? [String] {
            return Set(array)
        }
        return []
    }
}

public actor CacheManager {
    public static let shared = CacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    public init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("com.dennesssy.brewbar", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func cacheData(_ data: Data, forKey key: String) {
        let sanitizedKey = key.replacingOccurrences(of: "/", with: "_")
        let fileURL = cacheDirectory.appendingPathComponent(sanitizedKey)
        try? data.write(to: fileURL)
    }

    public func cachedData(forKey key: String) -> Data? {
        let sanitizedKey = key.replacingOccurrences(of: "/", with: "_")
        let fileURL = cacheDirectory.appendingPathComponent(sanitizedKey)
        return try? Data(contentsOf: fileURL)
    }

    public func clearAllCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
