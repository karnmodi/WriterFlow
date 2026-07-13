import Carbon.HIToolbox
import Foundation

/// Global ⌥ Space hotkey via Carbon RegisterEventHotKey.
final class GlobalHotkey {
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x5746_4C57), id: 1) // "WFLW"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    var onTrigger: (() -> Void)?

    func install() -> Bool {
        guard hotKeyRef == nil else { return true }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref

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
