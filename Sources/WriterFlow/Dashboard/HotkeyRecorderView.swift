import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click-to-record global hotkey control. Captures the next key+modifier combo via a local
/// `NSEvent` monitor (swallowing the event so it never leaks into whatever's behind the
/// button), requires at least one modifier so it can't shadow normal typing, and lets Esc
/// cancel. The actual collision check happens one level up — `AppDelegate` attempts real OS
/// registration and reverts on failure — this view only captures the combo.
struct HotkeyRecorderView: View {
    @Binding var combo: HotkeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "command")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isRecording ? Color.accentColor : .secondary)
                Text(isRecording ? "Press a key combo…" : combo.displayString)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isRecording {
                    Text("Esc to cancel")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 240)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: isRecording ? 2 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Recording hotkey" : "Hotkey \(combo.displayString)")
        .accessibilityHint("Click to change the global shortcut")
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            var carbonModifiers: UInt32 = 0
            if event.modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }

            guard carbonModifiers != 0 else { return nil }

            combo = HotkeyCombo(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
    }
}
