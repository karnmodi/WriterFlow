import Carbon.HIToolbox
import Foundation

/// Global hotkey via Carbon RegisterEventHotKey. Combo is configurable (Stage 3.4's hotkey
/// recorder) — default ⌃⌥Space avoids conflict with Spotlight (⌘Space) and other assistants
/// commonly bound to plain ⌥Space.
final class GlobalHotkey {
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x5746_4C57), id: 1) // "WFLW"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var installedCombo: HotkeyCombo?

    var onTrigger: (() -> Void)?

    /// Registers `combo` with the OS. Returns `false` (leaving any previous registration
    /// untouched) if another app already owns that exact key+modifier combination —
    /// `RegisterEventHotKey` is the actual collision check, not a static guess-list.
    @discardableResult
    func install(combo: HotkeyCombo = .default) -> Bool {
        if installedCombo == combo, hotKeyRef != nil { return true }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }

        // New combo registered successfully — release the old one now, not before,
        // so a failed re-registration leaves the previous hotkey still working.
        unregister()
        hotKeyRef = ref
        installedCombo = combo

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotkeyHandler,
            1,
            &spec,
            selfPtr,
            &handlerRef
        )
        guard installStatus == noErr else {
            unregister()
            return false
        }
        return true
    }

    func uninstall() {
        unregister()
        onTrigger = nil
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }

    fileprivate func handleHotKey(_ id: EventHotKeyID) {
        guard id.signature == Self.hotKeyID.signature, id.id == Self.hotKeyID.id else { return }
        let callback = onTrigger
        DispatchQueue.main.async {
            callback?()
        }
    }
}

private func globalHotkeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }

    let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
    hotkey.handleHotKey(id)
    return noErr
}
