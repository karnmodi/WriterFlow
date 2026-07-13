import SwiftUI

/// The 28 px pill icon shown next to the focused field.
struct FloatingIconView: View {
    var onClick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onClick) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 6, x: 0, y: 2)

                Image(systemName: "highlighter")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .purple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: 28, height: 28)
            .scaleEffect(hovering ? 1.06 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
