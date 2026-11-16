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
                Button("Show Floating Search Bar") {
                    AppPresentationManager.shared.toggleFloatingPanel()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

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

        // Register global key monitor for Option+Space or Option+F
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Option + Space
            if event.modifierFlags.contains(.option) && event.keyCode == 49 {
                AppPresentationManager.shared.toggleFloatingPanel()
                return nil
            }
            return event
        }
    }
}
