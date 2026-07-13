import AppKit
import SwiftUI

enum ToastStyle {
    case success
    case error
    case info

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .success: .green
        case .error: .orange
        case .info: .blue
        }
    }

    var barColor: Color {
        switch self {
        case .success: .green
        case .error: .orange
        case .info: .blue
        }
    }
}

/// Brief non-activating banner below the dock icon, with a shrinking timer bar.
@MainActor
enum MessageToast {
    private static var panel: FloatingPanel?
    private static var hideTask: Task<Void, Never>?

    struct Action {
        let icon: String
        let label: String
        let handler: () -> Void
    }

    static func show(
        _ message: String,
        style: ToastStyle = .info,
        duration: TimeInterval = 3.0,
        belowIcon iconFrame: CGRect? = nil,
        action: Action? = nil
    ) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let width: CGFloat = 220
        let height: CGFloat = action == nil ? 58 : 62
        let size = CGSize(width: width, height: height)
        let toast = FloatingPanel(size: size)
        toast.hasShadow = true
        toast.level = .floating

        let hosting = NSHostingView(rootView: MessageToastView(
            message: message,
            style: style,
            duration: duration,
            action: action
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        toast.contentView = hosting

        let screen = screenForIcon(iconFrame) ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            toast.setFrameOrigin(origin(for: size, belowIcon: iconFrame, on: screen))
        }

        toast.alphaValue = 0
        toast.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.10
            toast.animator().alphaValue = 1.0
        }

        panel = toast
        if style == .error {
            Log.engine.error("Toast: \(message, privacy: .public)")
        } else {
            Log.overlay.info("Toast: \(message, privacy: .public)")
        }

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
            ctx.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
            }
        })
        self.panel = nil
    }

    /// Default dock-icon frame when the live panel isn't available.
    static func defaultIconFrame(
        iconSize: CGSize = CGSize(width: 28, height: 28),
        iconBottomMargin: CGFloat = 36,
        on screen: NSScreen
    ) -> CGRect {
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - iconSize.width / 2,
            y: visible.minY + iconBottomMargin
        )
        return CGRect(origin: origin, size: iconSize)
    }

    private static func screenForIcon(_ iconFrame: CGRect?) -> NSScreen? {
        guard let iconFrame, !iconFrame.isEmpty else {
            return NSScreen.main ?? NSScreen.screens.first
        }
        return NSScreen.screens.first(where: { $0.frame.intersects(iconFrame) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private static func origin(for size: CGSize, belowIcon iconFrame: CGRect?, on screen: NSScreen) -> CGPoint {
        let visible = screen.visibleFrame
        let gap: CGFloat = 6
        let icon = iconFrame.flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultIconFrame(on: screen)

        var x = icon.midX - size.width / 2
        // Stack just above the dock icon — bottom-center, in context with the wave.
        var y = icon.maxY + gap

        if y + size.height > visible.maxY - 4 {
            y = icon.minY - size.height - gap
        }

        x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        y = min(max(y, visible.minY + 4), visible.maxY - size.height - 4)
        return CGPoint(x: x, y: y)
    }
}

private struct MessageToastView: View {
    let message: String
    let style: ToastStyle
    let duration: TimeInterval
    let action: MessageToast.Action?

    @State private var timerProgress: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: style.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(style.iconColor)

                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if let action {
                    Button(action: action.handler) {
                        Image(systemName: action.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(action.label)
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 9)
            .padding(.bottom, 7)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(style.barColor.opacity(0.18))
                    Capsule()
                        .fill(style.barColor.opacity(0.85))
                        .frame(width: max(0, geo.size.width * timerProgress))
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 11)
            .padding(.bottom, 7)
        }
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        }
        .onAppear {
            timerProgress = 1.0
            withAnimation(.linear(duration: duration)) {
                timerProgress = 0
            }
        }
    }
}
