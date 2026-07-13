import SwiftUI

struct PreviewCardView: View {
    let actionTitle: String
    let text: String
    let isStreaming: Bool
    let canReplace: Bool
    var onReplace: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isStreaming {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView {
                Text(text.isEmpty ? "Thinking…" : text)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 120)

            HStack {
                Button("Discard", action: onDiscard)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Replace", action: onReplace)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(!canReplace || text.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 300)
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
