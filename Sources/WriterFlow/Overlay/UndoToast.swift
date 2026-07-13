import AppKit
import SwiftUI

/// Brief non-activating confirmation banner with a "Restore" action — shown
/// after a successful Replace so the user can undo within a short window.
@MainActor
enum UndoToast {
    private static var panel: FloatingPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(message: String, duration: TimeInterval = 5.0, onRestore: @escaping () -> Void) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let size = CGSize(width: 260, height: 56)
        let toast = FloatingPanel(size: size)
        toast.hasShadow = true
        toast.level = .floating

        let hosting = NSHostingView(rootView: UndoToastView(
            message: message,
            onRestore: {
                onRestore()
                dismiss()
            }
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        toast.contentView = hosting

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let origin = CGPoint(
                x: vf.midX - size.width / 2,
                y: vf.maxY - size.height - 12
            )
            toast.setFrameOrigin(origin)
        }

        toast.alphaValue = 0
        toast.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            toast.animator().alphaValue = 1.0
        }

        panel = toast

        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    static func dismiss() {
        hideTask?.cancel()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        })
        self.panel = nil
    }
}

private struct UndoToastView: View {
    let message: String
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button("Restore", action: onRestore)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        }
    }
}
