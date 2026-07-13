import Combine
import Foundation

enum IconMode: String, CaseIterable, Sendable {
    case onTyping
    case hotkeyOnly
    case alwaysOnFocus
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    @Published var iconMode: IconMode {
        didSet { defaults.set(iconMode.rawValue, forKey: Keys.iconMode) }
    }

    @Published var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.isPaused) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// Last 5 Custom-action instructions, most recent first — quick-repeat chips.
    @Published var recentCustomInstructions: [String] {
        didSet { defaults.set(recentCustomInstructions, forKey: Keys.recentCustomInstructions) }
    }

    func recordCustomInstruction(_ instruction: String) {
        var list = recentCustomInstructions.filter { $0 != instruction }
        list.insert(instruction, at: 0)
        recentCustomInstructions = Array(list.prefix(5))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let modeRaw = defaults.string(forKey: Keys.iconMode) ?? IconMode.onTyping.rawValue
        self.iconMode = IconMode(rawValue: modeRaw) ?? .onTyping
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        // Default launchAtLogin to true only if the key has never been set.
        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            self.launchAtLogin = true
            defaults.set(true, forKey: Keys.launchAtLogin)
        } else {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
        self.recentCustomInstructions = defaults.stringArray(forKey: Keys.recentCustomInstructions) ?? []
    }

    private enum Keys {
        static let iconMode      = "wf.iconMode"
        static let isPaused      = "wf.isPaused"
        static let launchAtLogin = "wf.launchAtLogin"
        static let recentCustomInstructions = "wf.recentCustomInstructions"
    }
}
