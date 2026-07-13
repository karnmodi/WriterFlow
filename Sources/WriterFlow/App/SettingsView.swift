import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.title2).bold()
                Text("Paste your Azure OpenAI API key. It's validated with a 1-token test call, then stored in the Keychain — never in logs or UserDefaults.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                SecureField("API key", text: $viewModel.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isValidating)

                HStack(spacing: 10) {
                    Button {
                        viewModel.validateAndSave()
                    } label: {
                        if viewModel.isValidating {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Validate & Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isValidating || viewModel.apiKeyInput.isEmpty)

                    if let message = viewModel.statusMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(viewModel.statusIsError ? .red : .green)
                    }
                }
            }

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(width: 460, height: 260)
    }
}
