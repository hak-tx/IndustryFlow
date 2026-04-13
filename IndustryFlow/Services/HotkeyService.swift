import Foundation
import Carbon.HIToolbox
import AppKit
import os

/// Detects a double-tap of the Control key to trigger dictation.
/// Listens for flagsChanged events (modifier key press/release) and fires
/// the callback when Control is pressed twice within a short time window.
final class HotkeyService {
    var onHotkeyPressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Maximum interval between two Control presses to count as a double-tap.
    private let doubleTapInterval: TimeInterval = 0.4

    /// Tracks the timestamp of the last Control key release.
    private var lastControlReleaseTime: TimeInterval = 0

    /// Tracks whether Control is currently held down.
    private var controlIsDown = false

    /// Guards against firing on key combos — if any other key or modifier
    /// was pressed while Control was held, the tap is disqualified.
    private var otherKeyDuringControl = false

    deinit {
        unregister()
    }

    func register() {
        // Clean up any existing tap
        unregister()

        // Listen for flagsChanged (modifier keys) AND keyDown (to detect combos)
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                service.handleEvent(event, type: type)
                // Always pass the event through — we never suppress modifier keys
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPointer
        ) else {
            Logger.hotkey.error("Failed to create event tap. Accessibility permission may be missing.")
            return
        }

        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Logger.hotkey.info("Global hotkey registered (double-tap Control)")
    }

    func unregister() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        Logger.hotkey.info("Global hotkey unregistered")
    }

    private func handleEvent(_ event: CGEvent, type: CGEventType) {
        if type == .keyDown {
            // A regular key was pressed while Control might be held — disqualify this tap
            if controlIsDown {
                otherKeyDuringControl = true
            }
            return
        }

        // flagsChanged event — check if Control state changed
        guard type == .flagsChanged else { return }

        let flags = event.flags
        let controlNowDown = flags.contains(.maskControl)

        // Check that no other modifiers are held (Cmd, Shift, Option)
        let otherModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate]
        let hasOtherModifiers = !flags.intersection(otherModifiers).isEmpty

        if controlNowDown && !controlIsDown {
            // Control was just pressed down
            controlIsDown = true
            otherKeyDuringControl = hasOtherModifiers
        } else if !controlNowDown && controlIsDown {
            // Control was just released
            controlIsDown = false

            // Only count as a clean tap if no other keys/modifiers were involved
            guard !otherKeyDuringControl && !hasOtherModifiers else {
                otherKeyDuringControl = false
                return
            }

            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = now - lastControlReleaseTime

            if elapsed < doubleTapInterval {
                // Double-tap detected
                Logger.hotkey.debug("Double-tap Control detected")
                lastControlReleaseTime = 0 // Reset to prevent triple-tap re-trigger
                DispatchQueue.main.async { [weak self] in
                    self?.onHotkeyPressed?()
                }
            } else {
                lastControlReleaseTime = now
            }
        }
    }
}
