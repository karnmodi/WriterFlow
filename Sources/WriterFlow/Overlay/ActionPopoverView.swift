import SwiftUI

/// Compact action list shown in the non-activating popover panel.
struct ActionPopoverView: View {
    let highlightedIndex: Int
    var onSelect: (WritingAction) -> Void

    private let actions = WritingAction.popoverOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                ActionRow(
                    action: action,
                    isHighlighted: index == highlightedIndex,
                    onSelect: { onSelect(action) }
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

private struct ActionRow: View {
    let action: WritingAction
    let isHighlighted: Bool
    var onSelect: () -> Void

    @State private var hovering = false

    private var isInteractive: Bool { action.isEnabled }

    var body: some View {
        Button(action: {
            guard isInteractive else { return }
            onSelect()
        }) {
            HStack(spacing: 10) {
                if let shortcut = action.shortcut {
                    Text("\(shortcut)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isInteractive ? .secondary : .tertiary)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.quaternary.opacity(isInteractive ? 1 : 0.5))
                        )
                } else {
                    Color.clear.frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isInteractive ? .primary : .tertiary)

                    if !isInteractive {
                        Text("Coming in Phase 2")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .onHover { hovering = $0 }
    }

    private var rowBackground: Color {
        if !isInteractive { return .clear }
        if isHighlighted { return Color.accentColor.opacity(0.22) }
        if hovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}
