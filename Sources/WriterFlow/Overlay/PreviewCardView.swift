import SwiftUI

struct PreviewCardView: View {
    let actionTitle: String
    let text: String
    let originalText: String
    let action: WritingAction?
    let isStreaming: Bool
    let canReplace: Bool
    var onReplace: () -> Void
    var onCopy: () -> Void
    var onRetry: () -> Void
    var onDiscard: () -> Void

    private var showsDiff: Bool {
        !isStreaming && action == .fixGrammar && !originalText.isEmpty
    }

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
                content
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 120)

            HStack(spacing: 8) {
                Button("Discard", action: onDiscard)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Retry", action: onRetry)
                    .disabled(isStreaming)
                Spacer()
                Button("Copy", action: onCopy)
                    .disabled(!canReplace || text.isEmpty)
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

    @ViewBuilder
    private var content: some View {
        if text.isEmpty {
            Text("Thinking…")
        } else if showsDiff {
            diffedText
        } else {
            Text(text)
        }
    }

    private var diffedText: Text {
        WordDiff.segments(from: originalText, to: text).enumerated().reduce(Text("")) { partial, item in
            let (index, segment) = item
            let prefix = index == 0 ? "" : " "
            var word = Text(prefix + segment.text)
            if segment.changed {
                word = word.foregroundStyle(.green).bold()
            }
            return partial + word
        }
    }
}
