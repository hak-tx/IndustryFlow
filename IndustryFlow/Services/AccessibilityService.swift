import Foundation
import ApplicationServices
import AppKit
import os

final class AccessibilityService {

    /// Known Electron app bundle ID prefixes. Electron apps report incorrect
    /// cursor positions ({location=0, length=0}) via Accessibility APIs, so
    /// we skip AX text insertion and go straight to pasteboard for these.
    /// Source: electron/electron#36337
    private static let electronBundlePrefixes: Set<String> = [
        "com.microsoft.VSCode",
        "com.visualstudio.code",
        "com.todesktop.",
        "com.slack.",
        "com.discord",
        "com.spotify.",
        "com.figma.",
        "com.notion.",
        "com.linear.",
        "com.1password.",
        "com.obsidian.",
        "com.lencx.chatgpt",
        "dev.zed.",
        "com.cursor.",
        "com.github.GitHubClient",
    ]

    /// Known Electron app name substrings (fallback check when bundle ID isn't matched).
    private static let electronAppNames: Set<String> = [
        "Electron", "Code", "Cursor", "Slack", "Discord", "Notion",
        "Figma", "Spotify", "Obsidian", "Linear", "1Password",
    ]

    // MARK: - Permission Checking

    static func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - App Detection

    /// Returns true if the given app is an Electron-based application.
    /// Electron apps have broken AX text cursor reporting, so we must use
    /// pasteboard insertion exclusively for them.
    static func isElectronApp(_ app: NSRunningApplication) -> Bool {
        if let bundleID = app.bundleIdentifier {
            for prefix in electronBundlePrefixes {
                if bundleID.hasPrefix(prefix) {
                    return true
                }
            }
        }

        // Fallback: check the executable path for "Electron" framework
        if let url = app.executableURL {
            let path = url.path
            if path.contains("Electron") || path.contains("electron") {
                return true
            }
        }

        return false
    }

    static func isElectronApp(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }
        return isElectronApp(app)
    }

    // MARK: - Focused Element Discovery

    /// Captures the focused text element in the currently frontmost app.
    /// Call this BEFORE showing any IndustryFlow UI to avoid capturing our own fields.
    func captureFocusedElement() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Logger.accessibility.warning("No frontmost application found")
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success else {
            Logger.accessibility.warning("Could not get focused element: \(result.rawValue)")
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    /// Gets the focused text element using a specific PID (for when we captured the app earlier).
    func getFocusedElement(forPID pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    // MARK: - Text Insertion

    /// Inserts text at the current cursor position in the focused element.
    ///
    /// Strategy order:
    /// 1. If the target app is Electron-based, skip straight to pasteboard (AX is broken).
    /// 2. Try direct AX value manipulation (cleanest, supports undo).
    /// 3. Fall back to pasteboard + simulated Cmd+V (universal).
    func insertText(_ text: String, into element: AXUIElement, targetPID: pid_t? = nil) -> Bool {
        // Skip AX for Electron apps — their cursor reporting is broken
        if let pid = targetPID, AccessibilityService.isElectronApp(pid: pid) {
            Logger.accessibility.info("Electron app detected — using pasteboard insertion directly")
            return insertViaPasteboard(text)
        }

        // Try direct AX value manipulation first
        if insertViaAccessibility(text, into: element) {
            return true
        }

        // Fall back to pasteboard-based insertion
        Logger.accessibility.info("AX insertion failed — falling back to pasteboard")
        return insertViaPasteboard(text)
    }

    /// Replaces existing text with new text in the focused element.
    /// Used after polishing to swap raw transcript with polished version.
    ///
    /// Only attempts replacement via Accessibility API (direct string manipulation).
    /// Does NOT attempt pasteboard-based replacement — research from production apps
    /// (Wispr Flow, Pindrop, open-wispr) shows that selecting text via simulated
    /// keystrokes (Shift+Arrow) is fatally fragile and breaks when: the user clicked
    /// elsewhere, the app scrolled, there's input lag, or text wrapping changed.
    ///
    /// If AX replacement fails, returns false and the caller can decide what to do
    /// (e.g., copy polished text to clipboard and notify the user).
    func replaceText(original: String, replacement: String, in element: AXUIElement, targetPID: pid_t? = nil) -> Bool {
        // Skip for Electron apps
        if let pid = targetPID, AccessibilityService.isElectronApp(pid: pid) {
            Logger.accessibility.info("Electron app — AX replacement not possible, skipping")
            return false
        }

        return replaceViaAccessibility(original: original, replacement: replacement, in: element)
    }

    // MARK: - Live Streaming: Range-Based Replace

    /// Replaces a specific character range in the target element.
    /// Used for live dictation: as partial results come in, we replace the
    /// previously inserted range with the new full text.
    ///
    /// Returns the length of text now occupying the range, or -1 on failure.
    func replaceRange(in element: AXUIElement, start: Int, length: Int, with newText: String) -> Int {
        var currentValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)

        guard result == .success, let currentText = currentValue as? String else {
            return -1
        }

        let nsText = currentText as NSString
        let safeStart = min(start, nsText.length)
        let safeLength = min(length, nsText.length - safeStart)

        let replaced = nsText.replacingCharacters(
            in: NSRange(location: safeStart, length: safeLength),
            with: newText
        )

        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, replaced as CFTypeRef)
        guard setResult == .success else {
            return -1
        }

        // Move cursor to end of the new text
        let newEnd = safeStart + newText.count
        var newRange = CFRange(location: newEnd, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }

        return newText.count
    }

    /// Gets the current cursor position (location of selected text range) in the element.
    /// Returns -1 if it can't be read.
    func getCursorPosition(in element: AXUIElement) -> Int {
        var selectedRange: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        guard result == .success else { return -1 }

        var range = CFRange(location: 0, length: 0)
        if let axValue = selectedRange {
            AXValueGetValue(axValue as! AXValue, .cfRange, &range)
        }
        return range.location
    }

    // MARK: - Backspace Simulation (Electron Fallback)

    /// Simulates pressing the Delete (backspace) key N times.
    /// Used for Electron apps where AX range manipulation isn't available.
    func simulateBackspaces(count: Int) {
        guard count > 0 else { return }

        let source = CGEventSource(stateID: .combinedSessionState)

        for _ in 0..<count {
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false) else {
                continue
            }
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            usleep(2_000) // 2ms between keystrokes
        }
    }

    // MARK: - Strategy A: Direct Accessibility API

    private func insertViaAccessibility(_ text: String, into element: AXUIElement) -> Bool {
        // Get current value
        var currentValue: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)

        // Get current selected text range (cursor position)
        var selectedRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        )

        guard valueResult == .success,
              rangeResult == .success,
              let currentText = currentValue as? String else {
            Logger.accessibility.debug("Cannot read AX value/range — element may not support direct manipulation")
            return false
        }

        // Extract the CFRange from the AXValue
        var range = CFRange(location: 0, length: 0)
        if let axValue = selectedRange {
            AXValueGetValue(axValue as! AXValue, .cfRange, &range)
        }

        // Validate range — Electron apps report {0, 0} even when cursor is elsewhere.
        // If the text field has content but cursor reports position 0 with no selection,
        // this is likely a broken AX implementation. Fall back to pasteboard.
        if !currentText.isEmpty && range.location == 0 && range.length == 0 {
            // Double-check: try setting the range to see if the element actually supports it
            var testRange = CFRange(location: 0, length: 0)
            if let testValue = AXValueCreate(.cfRange, &testRange) {
                let testResult = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    testValue
                )
                if testResult != .success {
                    Logger.accessibility.debug("AX range is read-only — likely broken implementation")
                    return false
                }
            }
        }

        // Build new text with insertion at cursor position
        let nsText = currentText as NSString
        let insertionPoint = min(range.location, nsText.length)
        let newText = nsText.replacingCharacters(
            in: NSRange(location: insertionPoint, length: range.length),
            with: text
        )

        // Set the new value
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFTypeRef)
        guard setResult == .success else {
            Logger.accessibility.debug("Failed to set AX value: \(setResult.rawValue)")
            return false
        }

        // Verify the value was actually set (some apps return success but don't apply)
        var verifyValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &verifyValue)
        if let verifyText = verifyValue as? String, verifyText != newText {
            Logger.accessibility.debug("AX value set returned success but text did not change")
            return false
        }

        // Move cursor to end of inserted text
        let newCursorPosition = insertionPoint + text.count
        var newRange = CFRange(location: newCursorPosition, length: 0)
        if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRangeValue)
        }

        Logger.accessibility.info("Inserted \(text.count) characters via Accessibility API")
        return true
    }

    private func replaceViaAccessibility(original: String, replacement: String, in element: AXUIElement) -> Bool {
        var currentValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &currentValue)

        guard result == .success, let currentText = currentValue as? String else {
            return false
        }

        // Find the original text within the current value (search from end, since we just appended it)
        guard let range = currentText.range(of: original, options: .backwards) else {
            Logger.accessibility.warning("Could not find original text to replace")
            return false
        }

        let newText = currentText.replacingCharacters(in: range, with: replacement)
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFTypeRef)

        guard setResult == .success else {
            return false
        }

        // Verify replacement took effect
        var verifyValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &verifyValue)
        if let verifyText = verifyValue as? String, !verifyText.contains(replacement) {
            Logger.accessibility.debug("AX replacement returned success but text did not change")
            return false
        }

        // Position cursor at end of replacement
        let nsRange = NSRange(range, in: currentText)
        let newCursorPosition = nsRange.location + replacement.count
        var newCFRange = CFRange(location: newCursorPosition, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &newCFRange) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }

        Logger.accessibility.info("Replaced text via Accessibility API")
        return true
    }

    // MARK: - Strategy B: Pasteboard + Cmd+V (Universal Fallback)

    /// Inserts text via the system pasteboard and a simulated Cmd+V keystroke.
    ///
    /// This is the same approach used by Wispr Flow, JustDictate, and others.
    /// Steps (from node-insert-text):
    /// 1. Save current clipboard contents
    /// 2. Clear clipboard and write our text
    /// 3. Simulate Cmd+V
    /// 4. Restore original clipboard after 500ms
    ///
    /// 500ms restore delay matches Wispr Flow. Shorter values (300ms) cause
    /// clipboard races where the paste hasn't completed before restore.
    func insertViaPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // Save ALL pasteboard contents (not just string — preserves rich content, files, images)
        let savedItems = savePasteboardContents(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard write is committed before paste
        usleep(10_000) // 10ms

        // Simulate Cmd+V
        simulateKeyPress(keyCode: 0x09, flags: .maskCommand) // 'v' key

        // Restore pasteboard after 500ms (matches Wispr Flow timing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.restorePasteboardContents(pasteboard, items: savedItems)
        }

        Logger.accessibility.info("Inserted text via pasteboard fallback")
        return true
    }

    // MARK: - Pasteboard Save/Restore

    /// Saves all pasteboard items with all their types, preserving rich content.
    private func savePasteboardContents(_ pasteboard: NSPasteboard) -> [SavedPasteboardItem] {
        var savedItems: [SavedPasteboardItem] = []

        for item in pasteboard.pasteboardItems ?? [] {
            var typeData: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeData.append((type, data))
                }
            }
            if !typeData.isEmpty {
                savedItems.append(SavedPasteboardItem(typeData: typeData))
            }
        }

        return savedItems
    }

    /// Restores previously saved pasteboard contents.
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

    // MARK: - Key Event Simulation

    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cgSessionEventTap)
        usleep(5_000) // 5ms between key down and up for reliability
        keyUp.post(tap: .cgSessionEventTap)
    }
}

// MARK: - Types

private struct SavedPasteboardItem {
    let typeData: [(NSPasteboard.PasteboardType, Data)]
}
