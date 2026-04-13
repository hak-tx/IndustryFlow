import Foundation

enum Constants {
    static let appName = "IndustryFlow"
    static let bundleIdentifier = "com.industryflow.app"
    static let anthropicAPIURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicAPIVersion = "2023-06-01"
    static let defaultModel = "claude-haiku-4-5-20251001"
    static let doubleTapInterval: TimeInterval = 0.4
    static let maxPolishingTokens = 4096
    static let keychainServiceName = "com.industryflow.api-key"
    static let keychainAccountName = "anthropic-api-key"
    static let popoverWidth: CGFloat = 360
    static let popoverHeight: CGFloat = 480
    static let hotkeyDisplayName = "Control \u{00D7}2"

    /// Embedded API key for production distribution.
    /// Set this to your Anthropic API key to ship the app with a built-in key
    /// so end users don't need their own. Leave empty to require user-provided key.
    /// The Keychain key (user-provided in Settings) overrides this if set.
    static let embeddedAPIKey = ""
}
