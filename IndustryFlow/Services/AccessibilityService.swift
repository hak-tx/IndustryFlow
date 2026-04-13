import Foundation
import ApplicationServices
import AppKit
import os

/// Handles text input into other applications via CGEvent keystroke simulation.
/// This is the same mechanism Apple's native dictation uses — it goes through
/// the normal keyboard input pipeline and works in every app.
final class AccessibilityService {

    /// Serial queue for ALL CGEvent typing operations.
    /// Ensures typing calls execute one at a time, in order.
    /// Without this, concurrent typeText calls interleave characters
    /// and corrupt the cursor position.
    private let typingQueue = DispatchQueue(label: "com.industryflow.typing", qos: .userInteractive)

    /// Known Electron app bundle ID prefixes.
    private static let electronBundlePrefixes: Set<String> = [
        "com.microsoft.VSCode", "com.visualstudio.code", "com.todesktop.",
        "com.slack.", "com.discord", "com.spotify.", "com.figma.",
        "com.notion.", "com.linear.", "com.1password.", "com.obsidian.",
        "com.lencx.chatgpt", "dev.zed.", "com.cursor.",
        "com.github.GitHubClient",
    ]

    // MARK: - Permission Checking

    static func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func isElectronApp(_ app: NSRunningApplication) -> Bool {
        if let bundleID = app.bundleIdentifier {
            for prefix in electronBundlePrefixes {
                if bundleID.hasPrefix(prefix) { return true }
            }
        }
        if let url = app.executableURL {
            let path = url.path
            if path.contains("Electron") || path.contains("electron") { return true }
        }
        return false
    }

    // MARK: - Live Text Typing via CGEvent

    /// Queues text to be typed at the cursor. All typing goes through the serial
    /// typingQueue so calls never overlap. Safe to call rapidly from the main thread.
    func enqueueTyping(_ text: String) {
        guard !text.isEmpty else { return }
        typingQueue.async { [self] in
            self.typeTextSync(text)
        }
    }

    /// Queues backspace key presses on the serial typing queue.
    /// Used to delete previously typed text before retyping corrected version.
    func enqueueBackspaces(_ count: Int) {
        guard count > 0 else { return }
        typingQueue.async { [self] in
            self.backspaceSync(count)
        }
    }

    /// Blocks until all queued typing operations have completed.
    func drainTypingQueue() {
        typingQueue.sync {}
    }

    /// Backspaces synchronously. MUST only be called on typingQueue.
    private func backspaceSync(_ count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) else { continue }
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            usleep(1_000) // 1ms between backspaces
        }
    }

    /// Types text synchronously. MUST only be called on typingQueue.
    private func typeTextSync(_ text: String) {
        guard !text.isEmpty else { return }

        let source = CGEventSource(stateID: .combinedSessionState)

        // Type in chunks of up to 20 UTF-16 code units (CGEvent limit)
        let utf16 = Array(text.utf16)
        var offset = 0

        while offset < utf16.count {
            let chunkSize = min(20, utf16.count - offset)
            let chunk = Array(utf16[offset..<(offset + chunkSize)])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                offset += chunkSize
                continue
            }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)

            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)

            offset += chunkSize
            usleep(1_500) // 1.5ms between chunks for reliability
        }
    }

    // MARK: - Select and Replace (for polishing)

    /// Selects the last N characters behind the cursor and replaces them with new text.
    /// Used after Claude polishes the raw transcript — selects what we typed, pastes the polished version.
    ///
    /// Steps:
    /// 1. Simulate Shift+Left arrow × characterCount to select the typed text
    /// 2. Paste the replacement via clipboard + Cmd+V
    /// 3. Restore the original clipboard after 500ms
    func selectAndReplace(_ replacement: String, characterCount: Int) {
        guard characterCount > 0 else {
            // Nothing to select — just paste
            pasteText(replacement)
            return
        }

        let source = CGEventSource(stateID: .combinedSessionState)

        // Select backwards: Shift+Left arrow × characterCount
        // For large selections, use Shift+Cmd+Left (select to beginning of line) approach
        // But for reliability, use character-by-character selection
        for _ in 0..<characterCount {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: true), // Left arrow
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x7B, keyDown: false) else {
                continue
            }
            keyDown.flags = .maskShift
            keyUp.flags = .maskShift
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            usleep(500) // 0.5ms between arrows
        }

        // Small delay for selection to register
        usleep(50_000) // 50ms

        // Paste the replacement (overwrites the selection)
        pasteText(replacement)
    }

    // MARK: - Paste via Clipboard

    /// Pastes text at the current cursor/selection via clipboard + simulated Cmd+V.
    /// Saves and restores clipboard contents.
    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard
        let savedItems = savePasteboardContents(pasteboard)

        // Write our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        usleep(10_000) // 10ms for pasteboard write to commit

        // Cmd+V
        simulateKeyPress(keyCode: 0x09, flags: .maskCommand)

        // Restore clipboard after 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.restorePasteboardContents(pasteboard, items: savedItems)
        }
    }

    // MARK: - Key Simulation Helpers

    func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cgSessionEventTap)
        usleep(3_000)
        keyUp.post(tap: .cgSessionEventTap)
    }

    func simulateBackspaces(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) else { continue }
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            usleep(1_500)
        }
    }

    // MARK: - Pasteboard Save/Restore

    private func savePasteboardContents(_ pasteboard: NSPasteboard) -> [SavedPasteboardItem] {
        var saved: [SavedPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var typeData: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeData.append((type, data))
                }
            }
            if !typeData.isEmpty {
                saved.append(SavedPasteboardItem(typeData: typeData))
            }
        }
        return saved
    }

    private func restorePasteboardContents(_ pasteboard: NSPasteboard, items: [SavedPasteboardItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        for saved in items {
            let item = NSPasteboardItem()
            for (type, data) in saved.typeData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}

private struct SavedPasteboardItem {
    let typeData: [(NSPasteboard.PasteboardType, Data)]
}
