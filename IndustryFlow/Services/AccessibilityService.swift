import Foundation
import ApplicationServices
import AppKit
import os

final class AccessibilityService {

    // MARK: - Permission Checking

    static func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
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

    // MARK: - Text Insertion (Strategy A: Direct AX Manipulation)

    /// Inserts text at the current cursor position in the focused element.
    func insertText(_ text: String, into element: AXUIElement) -> Bool {
        // Try direct AX value manipulation first
        if insertViaAccessibility(text, into: element) {
            return true
        }

        // Fall back to pasteboard-based insertion
        Logger.accessibility.info("Falling back to pasteboard insertion")
        return insertViaPasteboard(text)
    }

    /// Replaces existing text with new text in the focused element.
    /// Used after polishing to swap raw transcript with polished version.
    func replaceText(original: String, replacement: String, in element: AXUIElement) -> Bool {
        // Try to find and select the original text, then replace it
        if replaceViaAccessibility(original: original, replacement: replacement, in: element) {
            return true
        }

        // Fallback: select all text we inserted and paste the replacement
        Logger.accessibility.info("Falling back to pasteboard replacement")
        return replaceViaPasteboard(original: original, replacement: replacement)
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
            Logger.accessibility.debug("Cannot read AX value/range, element may not support direct manipulation")
            return false
        }

        // Extract the CFRange from the AXValue
        var range = CFRange(location: 0, length: 0)
        if let axValue = selectedRange {
            AXValueGetValue(axValue as! AXValue, .cfRange, &range)
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

        // Find the original text within the current value
        guard let range = currentText.range(of: original, options: .backwards) else {
            Logger.accessibility.warning("Could not find original text to replace")
            return false
        }

        let newText = currentText.replacingCharacters(in: range, with: replacement)
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newText as CFTypeRef)

        guard setResult == .success else {
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

    // MARK: - Strategy B: Pasteboard Fallback

    private func insertViaPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulateKeyPress(keyCode: 0x09, flags: .maskCommand) // 'v' key

        // Restore pasteboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        Logger.accessibility.info("Inserted text via pasteboard fallback")
        return true
    }

    private func replaceViaPasteboard(original: String, replacement: String) -> Bool {
        // Select the original text length by sending Shift+Left arrow for each character,
        // then paste the replacement. This is fragile, so we use Cmd+A approach only
        // if we know the entire field content is our text.

        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Select the original text: use Cmd+A if the field only contains our text,
        // otherwise this fallback won't work perfectly
        // For now, select backwards by the length of the original text
        let charCount = original.count
        for _ in 0..<charCount {
            simulateKeyPress(keyCode: 0x7B, flags: .maskShift) // Left arrow + Shift
        }

        // Small delay for selection to register
        usleep(50_000)

        pasteboard.clearContents()
        pasteboard.setString(replacement, forType: .string)
        simulateKeyPress(keyCode: 0x09, flags: .maskCommand) // Cmd+V

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }

        Logger.accessibility.info("Replaced text via pasteboard fallback")
        return true
    }

    // MARK: - Key Event Simulation

    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidEventState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
