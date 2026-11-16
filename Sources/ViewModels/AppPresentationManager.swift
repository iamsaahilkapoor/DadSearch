import SwiftUI
import AppKit

@MainActor
public final class AppPresentationManager: ObservableObject {
    public static let shared = AppPresentationManager()

    public let searchViewModel = SearchViewModel()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var floatingPanel: NSPanel?
    private var mainWindow: NSWindow?

    public init() {}

    public func setup() {
        setupMenuBar()
        setupFloatingPanel()
    }

    // MARK: - Menu Bar Setup
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "DadSearch")
            button.target = self
            button.action = #selector(togglePopover)
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 460, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(viewModel: searchViewModel)
        )
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Floating Spotlight Panel Setup
    private final class KeySearchPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private func setupFloatingPanel() {
        let panel = KeySearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // SwiftUI view renders custom shadow

        let hostingView = NSHostingView(
            rootView: FloatingSearchPanel(viewModel: searchViewModel, onClose: { [weak self] in
                self?.hideFloatingPanel()
            })
        )
        panel.contentView = hostingView
        panel.center()

        self.floatingPanel = panel
    }

    public func toggleFloatingPanel() {
        guard let panel = floatingPanel else { return }
        if panel.isVisible {
            hideFloatingPanel()
        } else {
            showFloatingPanel()
        }
    }

    public func showFloatingPanel() {
        guard let panel = floatingPanel else { return }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func hideFloatingPanel() {
        floatingPanel?.orderOut(nil)
    }

    // MARK: - Standalone Main Window
    public func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "DadSearch — Universal Search"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.center()
            window.contentView = NSHostingView(rootView: MainWindowView(viewModel: searchViewModel))
            self.mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
