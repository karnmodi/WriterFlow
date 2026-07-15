import SwiftUI

/// Published by `OverlayController` so the already-mounted icon view can react to
/// state changes (e.g. an in-flight AI request) without recreating the hosting view.
@MainActor
final class IconState: ObservableObject {
    @Published var isBusy = false
}

/// Wave-lines dock icon fixed at bottom-center of the screen. Morphs into a small
/// spinner while `state.isBusy` (an action is streaming) — Stage 4.2 feel pass.
struct FloatingIconView: View {
    @ObservedObject var state: IconState
    var onClick: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onClick) {
            ZStack {
                WaveLinesIconView(size: 28)
                    .opacity(state.isBusy ? 0 : 1)
                ProgressView()
                    .controlSize(.small)
                    .opacity(state.isBusy ? 1 : 0)
            }
            .scaleEffect(hovering ? 1.10 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.75), value: hovering)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: state.isBusy)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(width: 28, height: 28)
        .onHover { hovering = $0 }
    }
}
