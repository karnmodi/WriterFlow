import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Clipboard save/restore and synthetic ⌘ key injection for cross-app paste.
enum ClipboardWriter {
    private struct SavedItem {
        let types: [NSPasteboard.PasteboardType: Data]
    }

    /// Activate target app, establish selection, paste replacement via clipboard.
    /// Returns false if key injection or clipboard setup failed.
    @MainActor
    static func executePaste(
        pid: pid_t,
        range: NSRange,
        replacement: String,
        replacingAll: Bool,
        role: String
    ) -> Bool {
        restoreFocus(pid: pid)

        let axApp = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(axApp)
        let focused = FocusedElementResolver.focusedElement(in: axApp)
            .flatMap { FocusedElementResolver.resolveEditable(from: $0) }

        let isWeb = role == AXRole.webArea
        let useSelectAll = isWeb || replacingAll

        if let focused, !useSelectAll {
            _ = AXCall.setRange(focused, AXAttr.selectedTextRange, range: range)
            Thread.sleep(forTimeInterval: 0.06)
        }

        let pasteboard = NSPasteboard.general
        let saved = savePasteboard(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(replacement, forType: .string) else {
            restorePasteboard(pasteboard, saved)
            Log.engine.error("Clipboard setup failed")
            return false
        }

        if useSelectAll {
            guard postCommandKey(CGKeyCode(kVK_ANSI_A), pid: pid) else {
                restorePasteboard(pasteboard, saved)
                return false
            }
            Thread.sleep(forTimeInterval: 0.08)
        }

        guard postCommandKey(CGKeyCode(kVK_ANSI_V), pid: pid) else {
            restorePasteboard(pasteboard, saved)
            return false
        }

        scheduleRestore(saved: saved)

        Log.engine.info(
            "Clipboard paste pid=\(pid, privacy: .public) web=\(isWeb, privacy: .public) selectAll=\(useSelectAll, privacy: .public)"
        )
        return true
    }

    // MARK: - Focus

    @MainActor
    @discardableResult
    static func restoreFocus(pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            Log.engine.error("restoreFocus: app not running pid=\(pid, privacy: .public)")
            return false
        }

        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Log.engine.debug(
            "restoreFocus before frontmost=\(frontBefore ?? -1, privacy: .public) target=\(pid, privacy: .public)"
        )

        app.activate()
        Thread.sleep(forTimeInterval: 0.05)

        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                Thread.sleep(forTimeInterval: 0.05)
                Log.engine.debug("restoreFocus: target is frontmost")
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        Log.engine.info("restoreFocus: timed out — will use postToPid fallback")
        return frontBefore != ProcessInfo.processInfo.processIdentifier
    }

    // MARK: - Pasteboard save/restore

    private static func savePasteboard(_ pasteboard: NSPasteboard) -> [SavedItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    types[type] = data
                }
            }
            return types.isEmpty ? nil : SavedItem(types: types)
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, _ saved: [SavedItem]) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }

        let items = saved.map { savedItem -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in savedItem.types {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func scheduleRestore(saved: [SavedItem]) {
        let snapshot = saved
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            restorePasteboard(NSPasteboard.general, snapshot)
        }
    }

    // MARK: - Key injection

    /// Post a Cmd+key event via the HID system tap (single delivery — avoids triple paste).
    @discardableResult
    static func postCommandKey(_ keyCode: CGKeyCode, pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags.maskCommand

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            Log.engine.error("postCommandKey: CGEvent creation failed key=\(keyCode, privacy: .public)")
            return false
        }

        down.flags = flags
        up.flags = flags

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        return true
    }
}
