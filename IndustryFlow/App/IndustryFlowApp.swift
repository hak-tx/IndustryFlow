import SwiftUI

@main
struct IndustryFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                appState: appDelegate.appState,
                permissionsService: appDelegate.permissionsService
            )
        }
    }
}
