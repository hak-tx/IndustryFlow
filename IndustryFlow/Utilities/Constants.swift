import Foundation
import Carbon.HIToolbox

enum Constants {
    static let appName = "IndustryFlow"
    static let bundleIdentifier = "com.industryflow.app"
    static let anthropicAPIURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let anthropicAPIVersion = "2023-06-01"
    static let defaultModel = "claude-haiku-4-5-20251001"
    static let defaultHotkeyKeyCode: UInt16 = UInt16(kVK_ANSI_D)
    static let defaultHotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
    static let maxPolishingTokens = 4096
    static let keychainServiceName = "com.industryflow.api-key"
    static let keychainAccountName = "anthropic-api-key"
    static let popoverWidth: CGFloat = 340
    static let popoverHeight: CGFloat = 420
}
