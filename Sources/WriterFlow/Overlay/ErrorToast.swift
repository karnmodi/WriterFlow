import AppKit
import SwiftUI

/// Brief non-activating error banner — does not steal focus from the text field.
@MainActor
enum ErrorToast {
    private static var panel: FloatingPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, duration: TimeInterval = 4.0) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let size = CGSize(width: 320, height: 56)
        let toast = FloatingPanel(size: size)
        toast.hasShadow = true
        toast.level = .floating

        let hosting = NSHostingView(rootView: ToastView(message: message))
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
        Log.engine.error("Error toast: \(message, privacy: .public)")

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

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        }
    }
}
