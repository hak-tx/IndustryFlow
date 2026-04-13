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

    /// Embedded API key — set YOUR key here for development.
    /// This eliminates the need to re-enter it after every build.
    /// For production: either keep embedded (you pay for API) or set to "" to require user key.
    /// User-provided key in Settings overrides this if set.
    ///
    /// HOW TO SET: Replace the empty string below with your Anthropic API key:
    ///   static let embeddedAPIKey = "sk-ant-api03-YOUR-KEY-HERE"
    static let embeddedAPIKey = ""
}
