import Foundation
import Carbon
import AppKit

public final class GlobalHotkeyManager: @unchecked Sendable {
    public static let shared = GlobalHotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    public func registerDefaultHotkey(handler: @escaping @Sendable () -> Void) {
        unregisterHotkey()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = HotkeyContext(action: handler)
        let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque())

        let handlerProc: EventHandlerUPP = { (_, _, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let context = Unmanaged<HotkeyContext>.fromOpaque(userData).takeUnretainedValue()
            context.action()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerProc,
            1,
            &eventType,
            ptr,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x44414453), id: 1) // "DADS"
        // 49 is Space keycode (kVK_Space), optionKey is 0x0800
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    public func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregisterHotkey()
    }
}

private final class HotkeyContext {
    let action: @Sendable () -> Void
    init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }
}
