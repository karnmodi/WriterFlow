import SwiftUI

struct PersonalizationView: View {
    @ObservedObject var viewModel: PersonalizationViewModel
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var memoryStore = MemoryStore.shared
    @ObservedObject private var appRuleStore = AppRuleStore.shared

    @State private var newSnippetText = ""
    @State private var newSnippetKind: MemoryNote.Kind = .fact
    @State private var newRuleIdentifier = ""

    private var budgetWarning: String? {
        let result = MemoryPromptBuilder.build(profile: settings.voiceProfile, notes: memoryStore.notes, appRule: nil)
        guard result.excludedCount > 0 else { return nil }
        return "\(result.excludedCount) older note(s) excluded from prompts — over the ~\(MemoryPromptBuilder.tokenBudget)-token memory budget. Disable a note below to make room for it instead."
    }

    var body: some View {
        DashboardFormContainer(
            header: DashboardPageHeader(
                title: "Personalization",
                subtitle: "Voice profile, memory notes, and per-app rules woven into every action so rewrites sound like you."
            )
        ) {
            VStack(alignment: .leading, spacing: DashboardChrome.sectionSpacing) {
                // A plain HStack, not ViewThatFits — ViewThatFits decides by probing each
                // candidate's *unconstrained* ideal size, and a long analysis paragraph reports
                // a huge ideal width, which was flipping this row in and out of side-by-side
                // depending on whether a result was showing. A fixed HStack always proposes a
                // bounded width to each card, so the (now height-capped + scrollable) analysis
                // box can never blow out the layout.
                HStack(alignment: .top, spacing: 12) {
                    voiceProfileCard
                    styleAnalysisCard
                }
                snippetsCard
                appRulesCard
            }
        }
    }

    // MARK: - Voice profile

    private var voiceProfileCard: some View {
        DashboardCard(
            title: "Voice Profile",
            subtitle: "Injected into every system prompt.",
            icon: "person.crop.circle",
            iconTint: .blue
        ) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("About my writing style")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $settings.voiceProfile.styleText)
                        .font(.callout)
                        .frame(height: 54)
                        .padding(5)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                                }
                        }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    LabeledField(label: "Sign as", text: $settings.voiceProfile.signOffName)
                    LabeledField(label: "Role", text: $settings.voiceProfile.role)
                    LabeledField(label: "Company", text: $settings.voiceProfile.company)
                    LabeledField(label: "Greeting/sign-off", text: $settings.voiceProfile.greeting)
                }

                if let budgetWarning {
                    StatusBanner(message: budgetWarning, tone: .warning)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Learned style

    private var styleAnalysisCard: some View {
        DashboardCard(
            title: "Learn Your Style",
            subtitle: "Optional — analyzes your own accepted outputs, never automatically.",
            icon: "sparkles",
            iconTint: .purple
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.analyzeStyle()
                    } label: {
                        if viewModel.isAnalyzing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Analyze My Writing Style", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAnalyzing)
                }

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                }

                if let proposed = viewModel.proposedStyleText {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView {
                            Text(proposed)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxHeight: 130)
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                                }
                        }
                        HStack {
                            Button("Add to Memory", action: viewModel.approveProposedStyle)
                                .buttonStyle(.borderedProminent)
                            Button("Discard", role: .cancel, action: viewModel.rejectProposedStyle)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Snippets & facts

    private var snippetsCard: some View {
        DashboardCard(
            title: "Snippets & Facts",
            subtitle: "Reusable facts the model may use — email, Calendly link, boilerplate. Click a note to read it in full.",
            icon: "note.text",
            iconTint: .green
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if memoryStore.notes.isEmpty {
                    Text("No memory notes yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(memoryStore.notes) { note in
                                MemoryNoteRow(note: note)
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(memoryStore.notes.count) * 46 + 8, 260))
                }

                HStack(spacing: 8) {
                    Picker("", selection: $newSnippetKind) {
                        Text("Fact").tag(MemoryNote.Kind.fact)
                        Text("Snippet").tag(MemoryNote.Kind.snippet)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    TextField("e.g. my email is ... / Calendly link", text: $newSnippetText)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newSnippetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { await memoryStore.add(kind: newSnippetKind, text: trimmed) }
                        newSnippetText = ""
                    }
                    .disabled(newSnippetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Per-app rules

    private var appRulesCard: some View {
        DashboardCard(
            title: "Per-App Rules",
            subtitle: "Tone, signature, and instruction overrides per app or site — plus the exclude switch.",
            icon: "square.grid.2x2",
            iconTint: .orange
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if appRuleStore.rules.isEmpty {
                    Text("No per-app rules yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(appRuleStore.rules, id: \.bundleOrSite) { rule in
                                AppRuleRow(rule: rule)
                            }
                        }
                    }
                    .frame(maxHeight: min(CGFloat(appRuleStore.rules.count) * 92 + 12, 320))
                }

                HStack(spacing: 8) {
                    TextField("App bundle id or site (e.g. com.tinyspeck.slackmacgap, gmail)", text: $newRuleIdentifier)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let trimmed = newRuleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { await appRuleStore.upsert(AppRule(bundleOrSite: trimmed)) }
                        newRuleIdentifier = ""
                    }
                    .disabled(newRuleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                DashboardSectionCaption(
                    text: "Excluding an app hides the WriterFlow icon there entirely, matched by bundle id (e.g. 1Password). Tone/signature/instruction match by site when known (gmail, linkedin, …), else by bundle id."
                )
            }
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct MemoryNoteRow: View {
    let note: MemoryNote
    @ObservedObject private var memoryStore = MemoryStore.shared
    @State private var showDetail = false

    private var kindIcon: String {
        switch note.kind {
        case .fact: return "doc.text.fill"
        case .snippet: return "paperclip"
        case .style: return "quote.bubble.fill"
        }
    }

    private var kindTint: Color {
        switch note.kind {
        case .fact: return .green
        case .snippet: return .teal
        case .style: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showDetail = true
            } label: {
                HStack(spacing: 8) {
                    IconBadge(systemName: kindIcon, tint: kindTint, size: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.kind.rawValue.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(note.text)
                            .font(.callout)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()
            Toggle("", isOn: Binding(
                get: { note.enabled },
                set: { newValue in Task { await memoryStore.setEnabled(id: note.id, enabled: newValue) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            Button(role: .destructive) {
                Task { await memoryStore.delete(id: note.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .sheet(isPresented: $showDetail) {
            MemoryNoteDetailView(note: note, kindIcon: kindIcon, kindTint: kindTint)
        }
    }
}

/// Full-text view for a memory note — rows truncate to one line for compactness, so this is
/// how you read a complete "Learn Your Style" note or a long snippet in full.
private struct MemoryNoteDetailView: View {
    let note: MemoryNote
    let kindIcon: String
    let kindTint: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(systemName: kindIcon, tint: kindTint)
                Text(note.kind.rawValue.capitalized)
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(note.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Last updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 220, idealHeight: 320)
    }
}

private struct AppRuleRow: View {
    let rule: AppRule
    @ObservedObject private var appRuleStore = AppRuleStore.shared

    private func binding(_ keyPath: WritableKeyPath<AppRule, String?>) -> Binding<String> {
        Binding(
            get: { rule[keyPath: keyPath] ?? "" },
            set: { newValue in
                var updated = rule
                updated[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                Task { await appRuleStore.upsert(updated) }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(nsImage: AppIconResolver.icon(forBundleID: rule.bundleOrSite))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(rule.bundleOrSite)
                    .font(.callout.bold())
                Spacer()
                Toggle("Excluded", isOn: Binding(
                    get: { rule.excluded },
                    set: { newValue in
                        var updated = rule
                        updated.excluded = newValue
                        Task { await appRuleStore.upsert(updated) }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Button(role: .destructive) {
                    Task { await appRuleStore.delete(bundleOrSite: rule.bundleOrSite) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 6)], spacing: 6) {
                TextField("Tone override", text: binding(\.tone))
                    .textFieldStyle(.roundedBorder)
                TextField("Signature", text: binding(\.signature))
                    .textFieldStyle(.roundedBorder)
                TextField("Custom instruction", text: binding(\.customInstruction))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}
