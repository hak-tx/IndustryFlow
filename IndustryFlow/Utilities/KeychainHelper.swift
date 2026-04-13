import Foundation
import Security

enum KeychainHelper {

    enum KeychainError: LocalizedError {
        case duplicateItem
        case itemNotFound
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .duplicateItem:
                return "An API key already exists in the keychain."
            case .itemNotFound:
                return "No API key found in the keychain."
            case .unexpectedStatus(let status):
                return "Keychain error: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error")"
            }
        }
    }

    /// File-based storage path in Application Support.
    /// Used instead of Keychain during development to avoid the password prompt
    /// on every rebuild (Xcode re-signs the binary, invalidating keychain ACLs).
    /// For production distribution, switch to Keychain with proper code signing.
    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("IndustryFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".api-key")
    }

    static func save(apiKey: String) throws {
        let data = Data(apiKey.utf8)
        try data.write(to: storageURL, options: [.atomic, .completeFileProtection])
    }

    static func retrieve() -> String? {
        guard let data = try? Data(contentsOf: storageURL) else {
            return nil
        }
        let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == true) ? nil : key
    }

    static func delete() {
        try? FileManager.default.removeItem(at: storageURL)
    }
}
