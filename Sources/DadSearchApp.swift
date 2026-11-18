import SwiftUI
import AppKit

@main
struct DadSearchMainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Standard window scene for standalone mode
        WindowGroup("DadSearch", id: "main-window") {
            MainWindowView(viewModel: AppPresentationManager.shared.searchViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Search") {
                Button("Show Floating Search Bar (⌥ Space)") {
                    AppPresentationManager.shared.toggleFloatingPanel()
                }
                .keyboardShortcut(" ", modifiers: [.option])

                Button("Show Main Window") {
                    AppPresentationManager.shared.showMainWindow()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app can receive keyboard input even as a utility/launcher
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        AppPresentationManager.shared.setup()

        // Register system-wide Global Carbon HotKey (⌥ + Space)
        GlobalHotkeyManager.shared.registerDefaultHotkey {
            Task { @MainActor in
                AppPresentationManager.shared.toggleFloatingPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.unregisterHotkey()
    }
}
