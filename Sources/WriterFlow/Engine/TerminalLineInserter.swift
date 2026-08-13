import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Replace the current terminal / TUI prompt line without touching scrollback.
///
/// Strategy (Claude Code / readline-style inputs):
/// 1. Focus the terminal app
/// 2. `Ctrl+U` twice to clear the draft (multiline-safe enough for CLI prompts)
/// 3. Paste the replacement via clipboard + Cmd+V
///
/// Never uses ⌘A or AX `setValue` on the terminal text blob.
enum TerminalLineInserter {
    @MainActor
    static func replace(pid: pid_t, with replacement: String) -> Bool {
        guard ClipboardWriter.restoreFocus(pid: pid) else {
            Log.engine.error("TerminalLineInserter: focus failed pid=\(pid, privacy: .public)")
            return false
        }

        // Clear current draft (Claude Code / bash readline).
        guard postControlKey(CGKeyCode(kVK_ANSI_U), pid: pid) else { return false }
        Thread.sleep(forTimeInterval: 0.05)
        _ = postControlKey(CGKeyCode(kVK_ANSI_U), pid: pid)
        Thread.sleep(forTimeInterval: 0.05)

        let pasteboard = NSPasteboard.general
        let saved = savePasteboard(pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(replacement, forType: .string) else {
            restorePasteboard(pasteboard, saved)
            return false
        }

        guard ClipboardWriter.postCommandKey(CGKeyCode(kVK_ANSI_V), pid: pid) else {
            restorePasteboard(pasteboard, saved)
            return false
        }

        scheduleRestore(saved: saved)
        Log.engine.info("TerminalLineInserter: replaced line pid=\(pid, privacy: .public)")
        return true
    }

    @discardableResult
    private static func postControlKey(_ keyCode: CGKeyCode, pid: pid_t) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags.maskControl

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            Log.engine.error("postControlKey: CGEvent creation failed key=\(keyCode, privacy: .public)")
            return false
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private struct SavedItem {
        let types: [NSPasteboard.PasteboardType: Data]
    }

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
}
