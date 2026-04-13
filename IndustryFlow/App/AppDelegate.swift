import AppKit
import SwiftUI
import ServiceManagement
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var clickOutsideMonitor: Any?

    // Shared state — single source of truth
    let appState = AppState()
    let permissionsService = PermissionsService()
    private var dictationViewModel: DictationViewModel?
    private let hotkeyService = HotkeyService()

    // Permission change observers
    private var permissionObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.app.info("IndustryFlow launching")

        dictationViewModel = DictationViewModel(
            appState: appState,
            permissionsService: permissionsService
        )

        setupStatusItem()
        setupPopover()
        setupHotkey()
        observePermissionChanges()
        checkFirstLaunch()

        Logger.app.info("IndustryFlow ready")
    }

    // MARK: - Status Bar Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "IndustryFlow"
            )
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

        // Close popover when user clicks outside
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
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
            permissionsService.refreshStatus()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Hotkey Setup

    /// Registers the hotkey service if accessibility is available, otherwise
    /// defers registration to when permission is granted (via notifications).
    private func setupHotkey() {
        hotkeyService.onHotkeyPressed = { [weak self] in
            self?.handleHotkeyTrigger()
        }

        if permissionsService.accessibilityGranted {
            hotkeyService.register()
        } else {
            Logger.hotkey.warning(
                "Accessibility not yet granted — hotkey will activate when permission is granted"
            )
        }
    }

    private func handleHotkeyTrigger() {
        guard let viewModel = dictationViewModel else { return }
        Logger.hotkey.info("Double-tap Control triggered")

        Task { @MainActor in
            viewModel.toggleDictation()
            updateMenuBarIcon()

            // Show popover briefly when recording starts
            if appState.isDictating,
               let button = statusItem?.button,
               !(popover?.isShown ?? false) {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    private func updateMenuBarIcon() {
        let symbolName = appState.isDictating ? "waveform.circle.fill" : "waveform"
        let description = appState.isDictating ? "IndustryFlow - Recording" : "IndustryFlow"
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: description
        )
    }

    // MARK: - Permission Change Monitoring

    /// Listens for permission changes from both PermissionsService and HotkeyService.
    /// Single coordination point — no duplicate polling.
    private func observePermissionChanges() {
        // When accessibility is restored, register the hotkey
        let restoredObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyPermissionRestored,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Logger.app.info("Accessibility restored — activating hotkey")

            if !self.hotkeyService.isActive {
                self.hotkeyService.register()
            }

            // Clear any permission warning from the UI
            if self.appState.errorMessage?.contains("Accessibility") == true {
                self.appState.clearError()
            }
        }
        permissionObservers.append(restoredObserver)

        // When accessibility is lost, alert the user
        let lostObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyPermissionLost,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Logger.app.error("Accessibility lost — notifying user")

            self.appState.errorMessage = """
            Accessibility permission was removed. \
            Double-tap Control is disabled until you re-enable it in \
            System Settings > Privacy & Security > Accessibility.
            """

            // Show the popover so the user sees the warning
            if let button = self.statusItem?.button, !(self.popover?.isShown ?? false) {
                self.popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
        permissionObservers.append(lostObserver)
    }

    // MARK: - First Launch & Login Item

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

    /// Registers IndustryFlow as a Login Item so it launches automatically on boot.
    /// Uses SMAppService (macOS 13+) — the modern, App Store-compatible API.
    static func registerLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                try service.register()
                Logger.app.info("Registered as login item")
            } catch {
                Logger.app.error("Failed to register login item: \(error.localizedDescription)")
            }
        }
    }

    static func unregisterLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                try service.unregister()
                Logger.app.info("Unregistered login item")
            } catch {
                Logger.app.error("Failed to unregister login item: \(error.localizedDescription)")
            }
        }
    }

    static var isLoginItemEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    // MARK: - Cleanup

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService.unregister()
        permissionsService.stopAllMonitoring()

        UserDefaults.standard.set(appState.selectedProfile.id, forKey: "selectedProfileID")

        for observer in permissionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        permissionObservers.removeAll()

        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }

        Logger.app.info("IndustryFlow shutting down")
    }
}
