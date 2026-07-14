import AppKit
import SwiftUI

struct HistoryDetailView: View {
    let event: ConversionEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Divider()

                HStack(alignment: .top, spacing: 20) {
                    column(title: "Before", text: event.input)
                    column(title: "After", text: event.output, diffAgainst: event.input)
                }

                if event.model != nil || event.tokensIn != nil || event.latencyMs != nil {
                    Divider()
                    metaRow
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(event.action).font(.title3.weight(.semibold))
                if event.accepted {
                    Label("Accepted", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            HStack(spacing: 8) {
                if let site = event.site {
                    Text(site)
                } else if let bundle = event.appBundleID {
                    Text(bundle)
                }
                Text(event.timestamp, style: .date)
                Text(event.timestamp, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func column(title: String, text: String, diffAgainst original: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button {
                    copyToClipboard(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(title.lowercased())")
            }

            if let original {
                diffText(new: text, old: original)
            } else {
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.body)
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func diffText(new: String, old: String) -> some View {
        WordDiff.segments(from: old, to: new).enumerated().reduce(Text("")) { partial, item in
            let (index, segment) = item
            let word = Text(segment.text)
                .foregroundColor(segment.changed ? .accentColor : .primary)
                .fontWeight(segment.changed ? .semibold : .regular)
            return index == 0 ? partial + word : partial + Text(" ") + word
        }
    }

    private var metaRow: some View {
        HStack(spacing: 16) {
            if let model = event.model {
                Label(model, systemImage: "cpu")
            }
            if let tokensIn = event.tokensIn, let tokensOut = event.tokensOut {
                Label("\(tokensIn)→\(tokensOut) tokens", systemImage: "text.word.spacing")
            }
            if let latencyMs = event.latencyMs {
                Label("\(latencyMs) ms", systemImage: "clock")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
