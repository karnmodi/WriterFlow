import SwiftUI

/// Compact action list shown in the non-activating popover panel.
struct ActionPopoverView: View {
    let highlightedIndex: Int
    let isCustomHighlighted: Bool
    let recommendedAction: WritingAction?
    let recentCustomInstructions: [String]
    @Binding var showPromptBuilderField: Bool
    @Binding var promptBuilderText: String
    @Binding var showCustomField: Bool
    @Binding var customText: String
    var onSelect: (WritingAction) -> Void
    var onPromptBuilderSubmit: (String) -> Void
    var onCustomSubmit: (String) -> Void
    var onCustomFocusRequested: () -> Void
    var onCustomOpen: () -> Void
    var onPromptBuilderFieldAppeared: () -> Void
    var onCustomFieldAppeared: () -> Void
    var onCustomCancelled: () -> Void
    var onPromptBuilderCancelled: () -> Void

    private let actions = WritingAction.popoverOrder

    @FocusState private var promptBuilderFieldFocused: Bool
    @FocusState private var customFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                ActionRow(
                    action: action,
                    isHighlighted: index == highlightedIndex && !isCustomHighlighted && !showPromptBuilderField,
                    isRecommended: action == recommendedAction,
                    onSelect: { onSelect(action) }
                )
            }

            if showPromptBuilderField {
                promptBuilderInputSection
            }

            Divider().padding(.vertical, 4)

            customSection
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

    private var promptBuilderInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Describe the prompt you need…", text: $promptBuilderText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary.opacity(0.5))
                )
                .focused($promptBuilderFieldFocused)
                .onSubmit { submitPromptBuilder() }
                .onExitCommand { cancelPromptBuilder() }
                .onAppear {
                    onPromptBuilderFieldAppeared()
                    promptBuilderFieldFocused = true
                }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var customSection: some View {
        if showCustomField {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Tell WriterFlow what to do…", text: $customText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary.opacity(0.5))
                    )
                    .focused($customFieldFocused)
                    .onSubmit { submitCustom() }
                    .onExitCommand { cancelCustom() }
                    .onAppear {
                        onCustomFieldAppeared()
                        customFieldFocused = true
                    }

                if !recentCustomInstructions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(recentCustomInstructions, id: \.self) { chip in
                                Button(chip) { customText = chip }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(.quaternary.opacity(0.5))
                                    )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        } else {
            Button {
                onCustomOpen()
            } label: {
                HStack(spacing: 10) {
                    Text("7")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.quaternary)
                        )
                    Text("Custom…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isCustomHighlighted ? Color.accentColor.opacity(0.22) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func submitPromptBuilder() {
        let trimmed = promptBuilderText.trimmingCharacters(in: .whitespacesAndNewlines)
        showPromptBuilderField = false
        promptBuilderText = ""
        guard !trimmed.isEmpty else {
            onPromptBuilderCancelled()
            return
        }
        onPromptBuilderSubmit(trimmed)
    }

    private func cancelPromptBuilder() {
        showPromptBuilderField = false
        promptBuilderText = ""
        onPromptBuilderCancelled()
    }

    private func submitCustom() {
        let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
        showCustomField = false
        customText = ""
        guard !trimmed.isEmpty else {
            onCustomCancelled()
            return
        }
        onCustomSubmit(trimmed)
    }

    private func cancelCustom() {
        showCustomField = false
        customText = ""
        onCustomCancelled()
    }
}

private struct ActionRow: View {
    let action: WritingAction
    let isHighlighted: Bool
    let isRecommended: Bool
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
                }

                Spacer(minLength: 0)

                if isRecommended {
                    Text("Suggested")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.15))
                        )
                }
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
