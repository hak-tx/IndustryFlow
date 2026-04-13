import Foundation
import AppKit
import os

/// Production-grade double-tap Control key detector.
///
/// Uses `NSEvent` global + local monitors as the primary detection mechanism.
/// NSEvent monitors are managed by AppKit's run loop and are more reliable than
/// raw CGEvent taps, which macOS can silently disable under load.
///
/// Robustness features:
/// - Automatic re-registration on wake from sleep, screen unlock, and workspace changes
/// - Periodic self-health checks that verify monitors are active
/// - Graceful handling of accessibility permission revocation
/// - Local + global monitors for coverage when IndustryFlow is focused or not
/// - Guards against false triggers from key combos (Ctrl+C, etc.)
final class HotkeyService {

    // MARK: - Public

    var onHotkeyPressed: (() -> Void)?

    /// Whether the hotkey system is currently active and listening.
    private(set) var isActive: Bool = false

    /// Maximum interval between two Control releases to count as a double-tap.
    var doubleTapInterval: TimeInterval = 0.35

    // MARK: - Private State

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var healthCheckTimer: Timer?
    private var systemObservers: [NSObjectProtocol] = []

    /// Timestamp of the last clean Control key release.
    private var lastControlReleaseTime: TimeInterval = 0

    /// Whether Control is currently held down.
    private var controlIsDown = false

    /// If any other key or modifier was pressed during this Control hold, disqualify it.
    private var tainted = false

    /// Monotonic clock source — resilient across sleep/wake unlike ProcessInfo.systemUptime.
    private var lastControlReleaseMach: UInt64 = 0

    /// Generation counter — incremented on each register() call to invalidate stale closures.
    private var generation: Int = 0

    deinit {
        teardown()
    }

    // MARK: - Registration

    func register() {
        generation += 1
        teardown()

        guard AccessibilityService.isAccessibilityEnabled() else {
            Logger.hotkey.warning("Cannot register hotkey — accessibility not granted")
            isActive = false
            return
        }

        installMonitors()
        installSystemObservers()
        startHealthCheck()

        isActive = true
        Logger.hotkey.info("Hotkey service activated (double-tap Control)")
    }

    func unregister() {
        teardown()
    }

    // MARK: - Monitor Installation

    private func installMonitors() {
        removeMonitors()

        // Global monitor: fires for events in OTHER applications
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
        }

        // Local monitor: fires for events when IndustryFlow itself is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event // Always pass through — never swallow events
        }

        Logger.hotkey.debug("NSEvent monitors installed")
    }

    private func removeMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - System Event Observers (re-register on system state changes)

    private func installSystemObservers() {
        removeSystemObservers()

        let ws = NSWorkspace.shared
        let nc = ws.notificationCenter
        let capturedGeneration = generation

        // Re-register after wake from sleep
        let wakeObserver = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.generation == capturedGeneration else { return }
            Logger.hotkey.info("System woke from sleep — re-registering hotkey monitors")
            self.installMonitors()
            self.resetTapState()
        }
        systemObservers.append(wakeObserver)

        // Re-register after screen unlock
        let unlockObserver = nc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.generation == capturedGeneration else { return }
            Logger.hotkey.info("Screens woke — re-registering hotkey monitors")
            self.installMonitors()
            self.resetTapState()
        }
        systemObservers.append(unlockObserver)

        // Re-register on user session activation (fast user switching)
        let sessionObserver = nc.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.generation == capturedGeneration else { return }
            Logger.hotkey.info("User session became active — re-registering hotkey monitors")
            self.installMonitors()
            self.resetTapState()
        }
        systemObservers.append(sessionObserver)

        // Monitor for accessibility changes via distributed notifications
        let axObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.generation == capturedGeneration else { return }
            Logger.hotkey.info("Accessibility API notification received — verifying permissions")
            if AccessibilityService.isAccessibilityEnabled() {
                self.installMonitors()
            } else {
                Logger.hotkey.error("Accessibility permission revoked — hotkey disabled")
                self.removeMonitors()
                self.isActive = false
            }
        }
        systemObservers.append(axObserver)
    }

    private func removeSystemObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        for observer in systemObservers {
            nc.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        systemObservers.removeAll()
    }

    // MARK: - Health Check (periodic self-verification)

    private func startHealthCheck() {
        healthCheckTimer?.invalidate()

        // Every 30 seconds, verify monitors are still alive and permissions still granted
        let capturedGeneration = generation
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.generation == capturedGeneration else { return }
            self.performHealthCheck()
        }
    }

    private func performHealthCheck() {
        // Check if accessibility is still granted
        guard AccessibilityService.isAccessibilityEnabled() else {
            Logger.hotkey.error("Health check: accessibility permission lost — disabling hotkey")
            isActive = false
            removeMonitors()
            // Post notification so the UI can alert the user
            NotificationCenter.default.post(name: .hotkeyPermissionLost, object: nil)
            return
        }

        // If monitors were somehow removed, reinstall them
        if globalMonitor == nil || localMonitor == nil {
            Logger.hotkey.warning("Health check: monitors missing — reinstalling")
            installMonitors()
        }

        // Ensure we're marked active
        if !isActive {
            isActive = true
            NotificationCenter.default.post(name: .hotkeyPermissionRestored, object: nil)
            Logger.hotkey.info("Health check: hotkey service restored")
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Any regular key pressed while Control is held disqualifies this tap
            if controlIsDown {
                tainted = true
            }

        case .flagsChanged:
            handleFlagsChanged(event)

        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let controlNowDown = flags.contains(.control)

        // If other modifiers are held (Cmd, Shift, Option), taint this tap
        let otherModifiers: NSEvent.ModifierFlags = [.command, .shift, .option]
        if !flags.intersection(otherModifiers).isEmpty {
            tainted = true
        }

        if controlNowDown && !controlIsDown {
            // Control pressed down
            controlIsDown = true
            // Only reset taint if no other modifiers are held right now
            tainted = !flags.intersection(otherModifiers).isEmpty

        } else if !controlNowDown && controlIsDown {
            // Control released
            controlIsDown = false

            guard !tainted else {
                tainted = false
                return
            }

            let now = machTimeSeconds()

            if lastControlReleaseMach > 0 {
                let elapsed = now - lastControlReleaseMach
                if elapsed < doubleTapInterval {
                    // Double-tap detected
                    lastControlReleaseMach = 0 // Reset — prevent triple-tap re-trigger
                    Logger.hotkey.debug("Double-tap Control detected")
                    DispatchQueue.main.async { [weak self] in
                        self?.onHotkeyPressed?()
                    }
                    return
                }
            }

            lastControlReleaseMach = now
        }
    }

    private func resetTapState() {
        controlIsDown = false
        tainted = false
        lastControlReleaseMach = 0
    }

    // MARK: - Teardown

    private func teardown() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        removeMonitors()
        removeSystemObservers()
        resetTapState()
        isActive = false
    }

    // MARK: - Monotonic Clock

    /// Returns seconds from the Mach absolute time clock.
    /// Unlike `ProcessInfo.systemUptime`, this clock is monotonic and not
    /// affected by system sleep on modern macOS (10.12+).
    private func machTimeSeconds() -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        if timebase.denom == 0 {
            mach_timebase_info(&timebase)
        }
        let machTime = mach_absolute_time()
        let nanos = machTime * UInt64(timebase.numer) / UInt64(timebase.denom)
        return TimeInterval(nanos) / 1_000_000_000
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the hotkey service detects that accessibility permission has been revoked.
    static let hotkeyPermissionLost = Notification.Name("com.industryflow.hotkeyPermissionLost")

    /// Posted when the hotkey service detects that accessibility permission has been restored.
    static let hotkeyPermissionRestored = Notification.Name("com.industryflow.hotkeyPermissionRestored")
}
