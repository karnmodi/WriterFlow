import SwiftUI

/// Wave-lines dock icon fixed at bottom-center of the screen.
struct FloatingIconView: View {
    var onClick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onClick) {
            WaveLinesIconView(size: 28)
                .scaleEffect(hovering ? 1.10 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: hovering)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(width: 28, height: 28)
        .onHover { hovering = $0 }
    }
}
