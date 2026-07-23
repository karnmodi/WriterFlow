import SwiftUI

enum PromptBuilderPreviewPhase: Equatable {
    case analyzing
    case clarify
    case prompt
}

struct PreviewCardView: View {
    let actionTitle: String
    let variants: PreviewVariants
    let usesMultiVariant: Bool
    let promptBuilderPhase: PromptBuilderPreviewPhase?
    let clarifyQuestions: [PromptBuilderOutputParser.ClarifyQuestion]
    let clarifySelections: [String: String]
    let originalText: String
    let action: WritingAction?
    let isStreaming: Bool
    let canReplace: Bool
    let errorMessage: String?
    let streamStartedAt: Date?
    var onSelectVariant: (Int) -> Void
    var onSelectClarifyAnswer: (String, String) -> Void
    var onContinueClarify: () -> Void
    var onReplace: () -> Void
    var onCopy: () -> Void
    var onRetry: () -> Void
    var onDiscard: () -> Void

    private var activeText: String {
        // Custom can ask for a derivative artifact (title/summary/etc.) via the
        // `---INSERT---` marker convention (see `CustomOutputParser`) — strip it from what's
        // displayed. No other action's prompt ever produces this marker.
        guard action == .custom else { return variants.selectedText }
        return CustomOutputParser.parse(variants.selectedText).text
    }

    /// True once we know this Custom result is a derivative artifact that will be inserted
    /// above the existing content rather than replacing it — used to relabel the Replace
    /// button so the non-destructive behavior isn't a surprise.
    private var isInsertMode: Bool {
        action == .custom && CustomOutputParser.parse(variants.selectedText).mode == .insertBeforeContent
    }

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
        if let errorMessage, !errorMessage.isEmpty {
            return "Couldn't finish — retry when ready"
        }
        if isStreaming, promptBuilderPhase == .analyzing {
            return "Understanding your brief…"
        }
        if isStreaming, promptBuilderPhase == .prompt {
            return "Generating…"
        }
        if isStreaming, activeText.isEmpty {
            return "Waiting for model…"
        }
        if isStreaming {
            return "Generating…"
        }
        if isClarifyMode { return "Clarify a few details" }
        if usesMultiVariant { return "Pick a variant, then Replace" }
        if showsPromptBuilderLayout { return "Review before replacing" }
        return "Review before replacing"
    }

    private var cardWidth: CGFloat {
        usesMultiVariant ? 380 : 300
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            if showsPromptBuilderLayout {
                promptBuilderContent
            } else {
                rewriteContent
            }
            Divider().opacity(0.35)
            toolbar
        }
        .frame(width: cardWidth)
        .overlayCardChrome()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(actionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isStreaming, !usesMultiVariant {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var rewriteContent: some View {
        if let errorMessage, !errorMessage.isEmpty {
            errorBanner(errorMessage)
        }
        if usesMultiVariant {
            variantPicker
        }
        StreamingPreviewScroll(
            text: activeText,
            isStreaming: isStreaming,
            showsDiff: showsDiff,
            originalText: originalText,
            placeholder: waitingPlaceholder,
            height: usesMultiVariant ? 168 : 140,
            streamStartedAt: streamStartedAt
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var waitingPlaceholder: String {
        if let errorMessage, !errorMessage.isEmpty {
            return ""
        }
        return "Waiting for model…"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var variantPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<PreviewVariants.count, id: \.self) { index in
                VariantTab(
                    label: variantLabel(index),
                    isSelected: variants.selectedIndex == index,
                    isStreaming: isStreaming && !variants.completedIndices.contains(index),
                    shortcut: "\(index + 1)",
                    action: { onSelectVariant(index) }
                )
            }

            Spacer(minLength: 8)

            Label("← → to switch", systemImage: "arrow.left.arrow.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func variantLabel(_ index: Int) -> String {
        switch index {
        case 0: return "Option A"
        case 1: return "Option B"
        default: return "Option C"
        }
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(height: 200)
    }

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage, !errorMessage.isEmpty {
                errorBanner(errorMessage)
            }
            DashboardSectionCaption(text: "Prompt")
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

            StreamingPreviewScroll(
                text: activeText,
                isStreaming: isStreaming,
                showsDiff: false,
                originalText: "",
                placeholder: waitingPlaceholder,
                height: 180,
                streamStartedAt: streamStartedAt
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
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
                    enabled: canReplace && !activeText.isEmpty,
                    prominent: false,
                    action: onCopy
                )
                IconToolButton(
                    systemName: isInsertMode ? "text.insert" : "arrow.turn.down.left",
                    label: isInsertMode ? "Insert" : "Replace",
                    shortcut: "↵",
                    enabled: canReplace && !activeText.isEmpty,
                    prominent: true,
                    action: onReplace
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

/// Scrollable preview body that stays usable while tokens stream in —
/// grows with content, shows a scrollbar, and pins to the latest text
/// during generation so long rewrites don't trap the user at the top.
private struct StreamingPreviewScroll: View {
    let text: String
    let isStreaming: Bool
    let showsDiff: Bool
    let originalText: String
    let placeholder: String
    let height: CGFloat
    let streamStartedAt: Date?

    private let bottomID = "preview-stream-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    if text.isEmpty {
                        waitingStatus
                    } else if showsDiff {
                        diffedText
                    } else {
                        Text(text)
                    }
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)
                .id(bottomID)
            }
            .frame(height: height)
            .onChange(of: text) { _, _ in
                guard isStreaming, !text.isEmpty else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onAppear {
                guard !text.isEmpty else { return }
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var waitingStatus: some View {
        if placeholder.isEmpty {
            EmptyView()
        } else if isStreaming, let started = streamStartedAt {
            TimelineView(.periodic(from: started, by: 0.5)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(started)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(placeholder)
                        .foregroundStyle(.secondary)
                    Text(progressCaption(seconds: seconds))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text(placeholder)
                .foregroundStyle(.secondary)
        }
    }

    private func progressCaption(seconds: Int) -> String {
        if seconds < 2 {
            return "Starting request…"
        }
        if seconds < 8 {
            return "Waiting \(seconds)s — model is preparing a reply"
        }
        return "Waiting \(seconds)s — high load can delay the first token"
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

// MARK: - Overlay chrome (shared with Dashboard tokens)

extension View {
    func overlayCardChrome() -> some View {
        background {
            RoundedRectangle(cornerRadius: DashboardChrome.cardCornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: DashboardChrome.cardCornerRadius, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardChrome.cardCornerRadius, style: .continuous))
    }
}

private struct VariantTab: View {
    let label: String
    let isSelected: Bool
    let isStreaming: Bool
    let shortcut: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                if isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(label) (\(shortcut))")
        .onHover { hovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if hovering { return Color.primary.opacity(0.06) }
        return Color.primary.opacity(0.04)
    }

    private var borderColor: Color {
        isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.1)
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
