import AppKit
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    // Shared state
    let appState = AppState()
    let permissionsService = PermissionsService()
    private var dictationViewModel: DictationViewModel?
    private let hotkeyService = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("IndustryFlow launching")

        // Initialize the dictation view model
        dictationViewModel = DictationViewModel(
            appState: appState,
            permissionsService: permissionsService
        )

        setupStatusItem()
        setupPopover()
        setupHotkey()
        checkFirstLaunch()

        Logger.app.info("IndustryFlow ready")
    }

    // MARK: - Status Bar Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "IndustryFlow")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        guard let viewModel = dictationViewModel else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(
            width: Constants.popoverWidth,
            height: Constants.popoverHeight
        )
        popover.behavior = .transient
        popover.animates = true

        let contentView = MenuBarPopover(
            appState: appState,
            viewModel: viewModel,
            permissionsService: permissionsService
        )
        popover.contentViewController = NSHostingController(rootView: contentView)

        self.popover = popover

        // Monitor for clicks outside the popover to close it
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Refresh permissions status when opening
            permissionsService.refreshStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            // Make the popover the key window but don't activate the app
            // This keeps focus in the target app
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Global Hotkey

    private func setupHotkey() {
        hotkeyService.onHotkeyPressed = { [weak self] in
            guard let self, let viewModel = self.dictationViewModel else { return }
            Logger.hotkey.info("Global hotkey triggered")

            // Toggle dictation
            Task { @MainActor in
                viewModel.toggleDictation()

                // Show/update status in the popover briefly
                if self.appState.isDictating {
                    // Show popover to indicate recording started
                    if let button = self.statusItem?.button, !(self.popover?.isShown ?? false) {
                        self.popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                    }
                    // Update menu bar icon
                    self.statusItem?.button?.image = NSImage(
                        systemSymbolName: "waveform.circle.fill",
                        accessibilityDescription: "IndustryFlow - Recording"
                    )
                } else {
                    // Restore menu bar icon
                    self.statusItem?.button?.image = NSImage(
                        systemSymbolName: "waveform",
                        accessibilityDescription: "IndustryFlow"
                    )
                }
            }
        }

        // Only register if accessibility is enabled (event tap requires it)
        if permissionsService.accessibilityGranted {
            hotkeyService.register()
        } else {
            Logger.hotkey.warning("Accessibility not granted — global hotkey not registered")
            // Register once accessibility is granted
            Task { @MainActor in
                // Poll for accessibility access
                for _ in 0..<120 {
                    try? await Task.sleep(for: .seconds(1))
                    if AccessibilityService.isAccessibilityEnabled() {
                        hotkeyService.register()
                        Logger.hotkey.info("Accessibility granted — hotkey now registered")
                        break
                    }
                }
            }
        }
    }

    // MARK: - First Launch

    private func checkFirstLaunch() {
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunched {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            appState.showOnboarding = true
        }

        // Load saved profile
        if let profileID = UserDefaults.standard.string(forKey: "selectedProfileID"),
           let profile = IndustryProfile.allProfiles.first(where: { $0.id == profileID }) {
            appState.selectedProfile = profile
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.unregister()

        // Save selected profile
        UserDefaults.standard.set(appState.selectedProfile.id, forKey: "selectedProfileID")

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        Logger.app.info("IndustryFlow shutting down")
    }
}
