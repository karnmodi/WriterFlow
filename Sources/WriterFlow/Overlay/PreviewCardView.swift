import SwiftUI

enum PromptBuilderPreviewPhase: Equatable {
    case analyzing
    case clarify
    case prompt
}

struct PreviewCardView: View {
    let actionTitle: String
    let text: String
    let promptBuilderPhase: PromptBuilderPreviewPhase?
    let clarifyQuestions: [PromptBuilderOutputParser.ClarifyQuestion]
    let clarifySelections: [String: String]
    let originalText: String
    let action: WritingAction?
    let isStreaming: Bool
    let canReplace: Bool
    var onSelectClarifyAnswer: (String, String) -> Void
    var onContinueClarify: () -> Void
    var onReplace: () -> Void
    var onCopy: () -> Void
    var onRetry: () -> Void
    var onDiscard: () -> Void

    private var showsDiff: Bool {
        !isStreaming && action == .fixGrammar && !originalText.isEmpty
    }

    private var showsPromptBuilderLayout: Bool {
        action == .promptBuilder
    }

    private var isClarifyMode: Bool {
        showsPromptBuilderLayout && promptBuilderPhase == .clarify
    }

    private var allQuestionsAnswered: Bool {
        !clarifyQuestions.isEmpty
            && clarifyQuestions.allSatisfy { clarifySelections[$0.id] != nil }
    }

    private var headerSubtitle: String {
        if isStreaming, promptBuilderPhase == .analyzing {
            return "Understanding your brief…"
        }
        if isStreaming, promptBuilderPhase == .prompt {
            return "Generating…"
        }
        if isClarifyMode { return "Clarify a few details" }
        if showsPromptBuilderLayout { return "Review before replacing" }
        return "Review before replacing"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            if showsPromptBuilderLayout {
                promptBuilderContent
            } else {
                contentArea
            }
            Divider().opacity(0.35)
            toolbar
        }
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(headerSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)
            }
            IconToolButton(
                systemName: "xmark",
                label: "Close",
                shortcut: "Esc",
                enabled: true,
                prominent: false,
                action: onDiscard
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var promptBuilderContent: some View {
        if isClarifyMode {
            clarifyContent
        } else {
            promptContent
        }
    }

    private var clarifyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(clarifyQuestions) { question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        FlowLayout(spacing: 6) {
                            ForEach(question.suggestions, id: \.self) { suggestion in
                                SuggestionChip(
                                    text: suggestion,
                                    isSelected: clarifySelections[question.id] == suggestion,
                                    action: { onSelectClarifyAnswer(question.id, suggestion) }
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(height: 200)
    }

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Prompt")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ScrollView {
                Group {
                    if text.isEmpty {
                        Text("Thinking…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(text)
                    }
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(height: 180)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var contentArea: some View {
        ScrollView {
            Group {
                if text.isEmpty {
                    Text("Thinking…")
                        .foregroundStyle(.secondary)
                } else if showsDiff {
                    diffedText
                } else {
                    Text(text)
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(height: 118)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            IconToolButton(
                systemName: "arrow.clockwise",
                label: "Retry",
                shortcut: "⌘R",
                enabled: !isStreaming,
                prominent: false,
                action: onRetry
            )
            Spacer(minLength: 0)

            if isClarifyMode {
                ContinueButton(
                    enabled: allQuestionsAnswered && !isStreaming,
                    action: onContinueClarify
                )
            } else {
                IconToolButton(
                    systemName: "doc.on.doc",
                    label: "Copy",
                    shortcut: "⌘C",
                    enabled: canReplace && !text.isEmpty,
                    prominent: false,
                    action: onCopy
                )
                IconToolButton(
                    systemName: "arrow.turn.down.left",
                    label: "Replace",
                    shortcut: "↵",
                    enabled: canReplace && !text.isEmpty,
                    prominent: true,
                    action: onReplace
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

private struct SuggestionChip: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if hovering { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.05)
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.12)
    }
}

private struct ContinueButton: View {
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("Continue")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Color.accentColor : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    enabled ? Color.accentColor.opacity(hovering ? 0.22 : 0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}

/// Simple wrapping layout for suggestion chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct IconToolButton: View {
    let systemName: String
    let label: String
    let shortcut: String?
    let enabled: Bool
    let prominent: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: prominent ? .semibold : .medium))
                .foregroundStyle(prominent && enabled ? Color.accentColor : .primary)
                .frame(width: 30, height: 28)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(helpText)
        .onHover { hovering = $0 }
    }

    private var helpText: String {
        if let shortcut {
            return "\(label) (\(shortcut))"
        }
        return label
    }

    private var backgroundColor: Color {
        if !enabled { return .clear }
        if prominent { return Color.accentColor.opacity(hovering ? 0.22 : 0.14) }
        if hovering { return Color.primary.opacity(0.08) }
        return .clear
    }
}
