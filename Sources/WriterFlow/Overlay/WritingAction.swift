import Foundation

/// The writing actions shown in the action popover.
enum WritingAction: CaseIterable, Sendable, Equatable {
    case elaborate
    case formal
    case casual
    case fixGrammar
    case reply
    case promptBuilder
    case custom

    var title: String {
        switch self {
        case .elaborate:      return "Elaborate"
        case .formal:         return "Formal"
        case .casual:         return "Casual"
        case .fixGrammar:     return "Fix Grammar"
        case .reply:          return "Reply"
        case .promptBuilder:  return "Prompt Builder"
        case .custom:         return "Custom"
        }
    }

    /// Keyboard shortcut digit (1–6) for the list-row actions.
    var shortcut: Int? {
        switch self {
        case .elaborate:      return 1
        case .formal:         return 2
        case .casual:         return 3
        case .fixGrammar:     return 4
        case .reply:          return 5
        case .promptBuilder:  return 6
        case .custom:         return nil
        }
    }

    var isEnabled: Bool { true }

    /// List rows shown in the popover — Custom has its own text-input row instead
    /// of a selectable list row (see `ActionPopoverView`), so it's excluded here.
    static var popoverOrder: [WritingAction] { allCases.filter { $0 != .custom } }

    /// Enabled actions only — used for keyboard navigation.
    static var enabledActions: [WritingAction] {
        allCases.filter(\.isEnabled)
    }

    static func matching(shortcut digit: Int) -> WritingAction? {
        enabledActions.first { $0.shortcut == digit }
    }
}
