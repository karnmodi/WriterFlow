import Carbon.HIToolbox
import Combine
import Foundation

enum IconMode: String, CaseIterable, Sendable {
    case onTyping
    case hotkeyOnly
    case alwaysOnFocus
}

/// A recordable global-hotkey combo — Carbon virtual key code + modifier bitmask
/// (`controlKey`/`optionKey`/`shiftKey`/`cmdKey` from `Carbon.HIToolbox`).
struct HotkeyCombo: Codable, Sendable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// ⌃⌥Space — chosen in Phase 0 to avoid colliding with Spotlight (⌘Space) or
    /// other assistants commonly bound to ⌥Space.
    static let `default` = HotkeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))

    var displayString: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + Self.keyName(for: keyCode)
    }

    /// Best-effort virtual-keycode → label map covering the keys people actually bind hotkeys to.
    private static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_Tab): "Tab",
            UInt32(kVK_Escape): "Esc", UInt32(kVK_Delete): "Delete",
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}

/// History retention window for the Stage 3.1 `conversions` table.
/// `.forever` disables the purge — nothing is auto-deleted.
enum RetentionPeriod: Int, CaseIterable, Sendable {
    case days30 = 30
    case days90 = 90
    case forever = -1

    var days: Int? { self == .forever ? nil : rawValue }

    var label: String {
        switch self {
        case .days30: return "30 days"
        case .days90: return "90 days"
        case .forever: return "Forever"
        }
    }
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
        didSet {
            guard let data = try? JSONEncoder().encode(recentCustomInstructions) else { return }
            WriterFlowDatabase.setSettingData(data, forKey: Keys.recentCustomInstructions)
        }
    }

    /// Stage 3.1 history retention window; defaults to 90 days.
    @Published var historyRetention: RetentionPeriod {
        didSet {
            defaults.set(historyRetention.rawValue, forKey: Keys.historyRetention)
            let days = historyRetention.days
            Task { await ConversionEventStore.shared.purgeExpired(retentionDays: days) }
        }
    }

    /// Stage 3.3 manual voice profile — injected into every system prompt via `MemoryPromptBuilder`.
    @Published var voiceProfile: VoiceProfile {
        didSet {
            if let data = try? JSONEncoder().encode(voiceProfile) {
                WriterFlowDatabase.setSettingData(data, forKey: Keys.voiceProfile)
            }
        }
    }

    /// Stage 3.4 global-hotkey combo. `AppDelegate` observes this and live-reinstalls
    /// `GlobalHotkey`; a failed OS-level registration (another app already owns the combo)
    /// reverts this to the last-good value and surfaces `hotkeyStatusMessage`.
    @Published var hotkeyCombo: HotkeyCombo {
        didSet {
            guard let data = try? JSONEncoder().encode(hotkeyCombo) else { return }
            defaults.set(data, forKey: Keys.hotkeyCombo)
        }
    }

    /// Transient (not persisted) feedback from the last hotkey registration attempt.
    @Published var hotkeyStatusMessage: String?
    @Published var hotkeyStatusIsError = false

    /// Stage 3.4 — when true, skip the AX write tiers entirely and always paste via clipboard.
    /// Useful for apps where AX writes are flaky or visibly glitch the field.
    @Published var forceClipboardFallback: Bool {
        didSet { defaults.set(forceClipboardFallback, forKey: Keys.forceClipboardFallback) }
    }

    func recordCustomInstruction(_ instruction: String) {
        var list = recentCustomInstructions.filter { $0 != instruction }
        list.insert(instruction, at: 0)
        recentCustomInstructions = Array(list.prefix(5))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let modeRaw = defaults.string(forKey: Keys.iconMode) ?? IconMode.alwaysOnFocus.rawValue
        self.iconMode = IconMode(rawValue: modeRaw) ?? .alwaysOnFocus
        self.isPaused = defaults.bool(forKey: Keys.isPaused)
        // Default launchAtLogin to true only if the key has never been set.
        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            self.launchAtLogin = true
            defaults.set(true, forKey: Keys.launchAtLogin)
        } else {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
        let encryptedRecent = WriterFlowDatabase.settingData(forKey: Keys.recentCustomInstructions)
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        let legacyRecent = defaults.stringArray(forKey: Keys.recentCustomInstructions) ?? []
        self.recentCustomInstructions = encryptedRecent ?? legacyRecent
        let retentionRaw = defaults.object(forKey: Keys.historyRetention) as? Int
        self.historyRetention = retentionRaw.flatMap(RetentionPeriod.init(rawValue:)) ?? .days90
        let encryptedVoice = WriterFlowDatabase.settingData(forKey: Keys.voiceProfile)
        if let data = encryptedVoice ?? defaults.data(forKey: Keys.voiceProfile),
           let profile = try? JSONDecoder().decode(VoiceProfile.self, from: data) {
            self.voiceProfile = profile
        } else {
            self.voiceProfile = VoiceProfile()
        }
        if let data = defaults.data(forKey: Keys.hotkeyCombo),
           let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data) {
            self.hotkeyCombo = combo
        } else {
            self.hotkeyCombo = .default
        }
        self.forceClipboardFallback = defaults.bool(forKey: Keys.forceClipboardFallback)
        var recentPersisted = encryptedRecent != nil
        if !recentPersisted, let data = try? JSONEncoder().encode(legacyRecent) {
            recentPersisted = WriterFlowDatabase.setSettingData(data, forKey: Keys.recentCustomInstructions)
        }
        var voicePersisted = encryptedVoice != nil
        if !voicePersisted, let data = try? JSONEncoder().encode(voiceProfile) {
            voicePersisted = WriterFlowDatabase.setSettingData(data, forKey: Keys.voiceProfile)
        }
        if recentPersisted {
            defaults.removeObject(forKey: Keys.recentCustomInstructions)
        }
        if voicePersisted {
            defaults.removeObject(forKey: Keys.voiceProfile)
        }
        Task {
            await ConversionEventStore.shared.migrateLegacyLogIfNeeded()
            await ConversionEventStore.shared.purgeExpired(retentionDays: self.historyRetention.days)
        }
    }

    private enum Keys {
        static let iconMode      = "wf.iconMode"
        static let isPaused      = "wf.isPaused"
        static let launchAtLogin = "wf.launchAtLogin"
        static let recentCustomInstructions = "wf.recentCustomInstructions"
        static let historyRetention = "wf.historyRetention"
        static let voiceProfile = "wf.voiceProfile"
        static let hotkeyCombo = "wf.hotkeyCombo"
        static let forceClipboardFallback = "wf.forceClipboardFallback"
    }
}
