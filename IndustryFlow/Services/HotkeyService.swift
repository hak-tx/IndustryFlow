import Foundation
import Carbon.HIToolbox
import AppKit
import os

final class HotkeyService {
    var onHotkeyPressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var registeredKeyCode: UInt16 = UInt16(kVK_ANSI_D)
    private var registeredModifiers: CGEventFlags = [.maskCommand, .maskShift]

    deinit {
        unregister()
    }

    func register(keyCode: UInt16? = nil, modifiers: CGEventFlags? = nil) {
        // Update registered combo if provided
        if let keyCode { registeredKeyCode = keyCode }
        if let modifiers { registeredModifiers = modifiers }

        // Clean up any existing tap
        unregister()

        // Create event tap for key down events
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // We need to capture self in the callback. Use an Unmanaged pointer.
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleEvent(event)
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

        Logger.hotkey.info("Global hotkey registered (keyCode: \(self.registeredKeyCode))")
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

    private func handleEvent(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check if this matches our registered hotkey
        let matchesKey = keyCode == registeredKeyCode

        // Check modifiers (mask out device-specific bits)
        let relevantFlags: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let pressedModifiers = flags.intersection(relevantFlags)
        let targetModifiers = registeredModifiers.intersection(relevantFlags)
        let matchesModifiers = pressedModifiers == targetModifiers

        if matchesKey && matchesModifiers {
            Logger.hotkey.debug("Hotkey pressed")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyPressed?()
            }
            // Suppress the event so it doesn't reach the target app
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
