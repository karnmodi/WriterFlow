import SwiftUI

// MARK: - Navigation

enum DashboardTab: String, CaseIterable, Identifiable {
    case history
    case personalization
    case settings
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .personalization: return "Personalization"
        case .settings: return "Settings"
        case .usage: return "Usage"
        }
    }

    var icon: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .personalization: return "person.text.rectangle"
        case .settings: return "gearshape"
        case .usage: return "chart.bar.xaxis"
        }
    }
}

// MARK: - Shared layout primitives

enum DashboardChrome {
    static let contentPadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 14
    static let cardCornerRadius: CGFloat = 10
}

struct DashboardPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rounded-square SF Symbol badge — the small colored icon used in card headers and,
/// at a smaller size, per-row kind icons. One shared component so every icon in the
/// Dashboard reads as part of the same system rather than ad hoc `Image(systemName:)` calls.
struct IconBadge: View {
    let systemName: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(tint.opacity(0.15))
            }
    }
}

struct DashboardCard<Content: View>: View {
    let title: String?
    var subtitle: String?
    var icon: String?
    var iconTint: Color = .accentColor
    @ViewBuilder var content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: String? = nil,
        iconTint: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconTint = iconTint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .center, spacing: 8) {
                    if let icon {
                        IconBadge(systemName: icon, tint: iconTint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DashboardChrome.cardCornerRadius, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: DashboardChrome.cardCornerRadius, style: .continuous)
                        .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

struct DashboardSectionCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatusBanner: View {
    enum Tone {
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "exclamationmark.circle.fill"
            }
        }
    }

    let message: String
    let tone: Tone

    init(message: String, tone: Tone) {
        self.message = message
        self.tone = tone
    }

    /// Compatibility shim for the original two-state banner (Settings tab's hotkey status).
    init(message: String, isError: Bool) {
        self.message = message
        self.tone = isError ? .error : .success
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tone.icon)
                .foregroundStyle(tone.color)
            Text(message)
                .font(.caption)
                .foregroundStyle(tone == .success ? .primary : tone.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone.color.opacity(0.08))
        }
    }
}

struct DashboardFormContainer<Content: View>: View {
    let header: DashboardPageHeader
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, DashboardChrome.contentPadding)
                    .padding(.top, DashboardChrome.contentPadding)
                    .padding(.bottom, 8)
                content
                    .padding(.horizontal, 8)
                    .padding(.bottom, DashboardChrome.contentPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let subtitle: String
    var emphasize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: DashboardChrome.cardCornerRadius, style: .continuous)
                .fill(emphasize ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: DashboardChrome.cardCornerRadius, style: .continuous)
                        .strokeBorder(
                            emphasize ? Color.accentColor.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.3),
                            lineWidth: 1
                        )
                }
        }
    }
}
