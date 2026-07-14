import SwiftUI

struct HistoryRowView: View {
    let event: ConversionEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: AppIconResolver.icon(forBundleID: event.appBundleID))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.action)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())

                    if event.accepted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    Spacer()

                    Text(event.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(preview)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
    }

    private var preview: String {
        let inputSnippet = event.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputSnippet = event.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if inputSnippet.isEmpty { return outputSnippet }
        return "\(inputSnippet) → \(outputSnippet)"
    }
}
