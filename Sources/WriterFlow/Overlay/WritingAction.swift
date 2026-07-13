import Foundation

/// The six writing actions shown in the action popover.
enum WritingAction: CaseIterable, Sendable, Equatable {
    case elaborate
    case formal
    case casual
    case fixGrammar
    case reply
    case custom

    var title: String {
        switch self {
        case .elaborate:   return "Elaborate"
        case .formal:      return "Formal"
        case .casual:      return "Casual"
        case .fixGrammar:  return "Fix Grammar"
        case .reply:       return "Reply"
        case .custom:      return "Custom"
        }
    }

    /// Keyboard shortcut digit (1–4) for the core four actions.
    var shortcut: Int? {
        switch self {
        case .elaborate:   return 1
        case .formal:      return 2
        case .casual:      return 3
        case .fixGrammar:  return 4
        case .reply, .custom: return nil
        }
    }

    /// Reply and Custom ship in Phase 2.
    var isEnabled: Bool {
        switch self {
        case .reply, .custom: return false
        default: return true
        }
    }

    /// Selectable actions in popover order (all six, including disabled).
    static var popoverOrder: [WritingAction] { allCases }

    /// Enabled actions only — used for keyboard navigation.
    static var enabledActions: [WritingAction] {
        allCases.filter(\.isEnabled)
    }

    static func matching(shortcut digit: Int) -> WritingAction? {
        enabledActions.first { $0.shortcut == digit }
    }
}
