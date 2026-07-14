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
        Form {
            voiceProfileSection
            styleAnalysisSection
            snippetsSection
            appRulesSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Voice profile

    private var voiceProfileSection: some View {
        Section("Voice Profile") {
            VStack(alignment: .leading, spacing: 4) {
                Text("About my writing style")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $settings.voiceProfile.styleText)
                    .frame(height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }
            TextField("Sign as", text: $settings.voiceProfile.signOffName)
            TextField("Role", text: $settings.voiceProfile.role)
            TextField("Company", text: $settings.voiceProfile.company)
            TextField("Preferred greeting/sign-off", text: $settings.voiceProfile.greeting)
            if let budgetWarning {
                Label(budgetWarning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Learned style

    private var styleAnalysisSection: some View {
        Section("Learned Style (optional)") {
            HStack(spacing: 10) {
                Button {
                    viewModel.analyzeStyle()
                } label: {
                    if viewModel.isAnalyzing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Analyze My Writing Style")
                    }
                }
                .disabled(viewModel.isAnalyzing)

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(viewModel.statusIsError ? .red : .secondary)
                }
            }
            Text("Runs only when you press this button, over your own recently accepted outputs — never automatically.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let proposed = viewModel.proposedStyleText {
                VStack(alignment: .leading, spacing: 6) {
                    Text(proposed)
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                    HStack {
                        Button("Add to Memory", action: viewModel.approveProposedStyle)
                            .buttonStyle(.borderedProminent)
                        Button("Discard", role: .cancel, action: viewModel.rejectProposedStyle)
                    }
                }
            }
        }
    }

    // MARK: - Snippets & facts

    private var snippetsSection: some View {
        Section("Snippets & Facts") {
            if memoryStore.notes.isEmpty {
                Text("No memory notes yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(memoryStore.notes) { note in
                MemoryNoteRow(note: note)
            }
            HStack {
                Picker("", selection: $newSnippetKind) {
                    Text("Fact").tag(MemoryNote.Kind.fact)
                    Text("Snippet").tag(MemoryNote.Kind.snippet)
                }
                .labelsHidden()
                .frame(width: 90)
                TextField("e.g. my email is ... / Calendly link", text: $newSnippetText)
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

    // MARK: - Per-app rules

    private var appRulesSection: some View {
        Section("Per-App Rules") {
            ForEach(appRuleStore.rules, id: \.bundleOrSite) { rule in
                AppRuleRow(rule: rule)
            }
            HStack {
                TextField("App bundle id or site (e.g. com.tinyspeck.slackmacgap, gmail)", text: $newRuleIdentifier)
                Button("Add") {
                    let trimmed = newRuleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { await appRuleStore.upsert(AppRule(bundleOrSite: trimmed)) }
                    newRuleIdentifier = ""
                }
                .disabled(newRuleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Excluding an app hides the WriterFlow icon there entirely, matched by bundle id (e.g. 1Password). Tone/signature/instruction match by site when known (gmail, linkedin, …), else by bundle id.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct MemoryNoteRow: View {
    let note: MemoryNote
    @ObservedObject private var memoryStore = MemoryStore.shared

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { note.enabled },
                set: { newValue in Task { await memoryStore.setEnabled(id: note.id, enabled: newValue) } }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(note.kind.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(note.text)
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer()
            Button(role: .destructive) {
                Task { await memoryStore.delete(id: note.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
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
                Button(role: .destructive) {
                    Task { await appRuleStore.delete(bundleOrSite: rule.bundleOrSite) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            TextField("Tone override", text: binding(\.tone))
                .textFieldStyle(.roundedBorder)
            TextField("Signature", text: binding(\.signature))
                .textFieldStyle(.roundedBorder)
            TextField("Custom instruction", text: binding(\.customInstruction))
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }
}
