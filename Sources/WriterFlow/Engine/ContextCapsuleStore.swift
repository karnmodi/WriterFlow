import Carbon.HIToolbox
import Foundation

private actor ConversationResultGate {
    private var continuation: CheckedContinuation<String?, Never>?
    private var resolved = false
    private var result: String?

    func install(_ continuation: CheckedContinuation<String?, Never>) {
        if resolved {
            continuation.resume(returning: result)
        } else {
            self.continuation = continuation
        }
    }

    func resolve(_ value: String?) {
        guard !resolved else { return }
        resolved = true
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }
}

struct ContextCapsule: Sendable, Equatable {
    let field: FocusedField
    let snapshot: FieldSnapshot
    let conversation: String?
    let site: String?
    let signals: ContextSignalBuilder.Signals
    let fingerprint: TargetFingerprint
    let capturedAt: Date
}

/// Active-field-only, volatile context. Nothing here is persisted or uploaded
/// until AutoActionCoordinator receives an explicit click/hotkey trigger.
@MainActor
final class ContextCapsuleStore {
    private(set) var current: ContextCapsule?
    private var activeField: FocusedField?
    private var refreshTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    private let debounce: Duration
    private let idleLifetime: Duration
    private let snapshotReader: @Sendable (pid_t, String?, Bool) async -> FieldSnapshot?
    private let conversationReader: @Sendable (pid_t, String) async -> String?
    private let secureInputEnabled: @Sendable () -> Bool

    init(
        debounce: Duration = .milliseconds(350),
        idleLifetime: Duration = .seconds(60),
        snapshotReader: @escaping @Sendable (pid_t, String?, Bool) async -> FieldSnapshot? = {
            await ContextExtractor.readFocusedField(
                pid: $0,
                bundleID: $1,
                allowClipboardFallback: $2
            )
        },
        conversationReader: @escaping @Sendable (pid_t, String) async -> String? = {
            await ConversationExtractor.extractConversation(pid: $0, excludingDraft: $1)
        },
        secureInputEnabled: @escaping @Sendable () -> Bool = { IsSecureEventInputEnabled() }
    ) {
        self.debounce = debounce
        self.idleLifetime = idleLifetime
        self.snapshotReader = snapshotReader
        self.conversationReader = conversationReader
        self.secureInputEnabled = secureInputEnabled
    }

    func focus(_ field: FocusedField) {
        if let activeField, !activeField.matchesRecommendationTarget(field) {
            clear()
        }
        activeField = field
        // Focus establishes identity only. Context collection begins after an
        // actual typing signal, or synchronously on an explicit command.
        restartExpiry()
    }

    func fieldChanged(_ field: FocusedField) {
        activeField = field
        scheduleRefresh()
    }

    func clear() {
        refreshTask?.cancel()
        expiryTask?.cancel()
        refreshTask = nil
        expiryTask = nil
        activeField = nil
        current = nil
    }

    /// Runs only after an explicit click/hotkey trigger (AutoActionCoordinator),
    /// i.e. past the same explicit-action gate the legacy manual popover already
    /// requires — so, like that path, it may fall back to the clipboard when
    /// `kAXValue` is structurally unreadable rather than silently generating
    /// from a near-empty snapshot.
    func captureForTrigger(field: FocusedField) async -> ContextCapsule? {
        refreshTask?.cancel()
        return await capture(field: field, allowConversationFallback: true, allowClipboardFallback: true)
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard let field = activeField else { return }
        let delay = debounce
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Passive awareness must never synthesize keyboard input — no
            // clipboard fallback here, only on an explicit trigger above.
            _ = await self.capture(field: field, allowConversationFallback: false, allowClipboardFallback: false)
        }
        restartExpiry()
    }

    private func restartExpiry() {
        expiryTask?.cancel()
        let lifetime = idleLifetime
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    private func capture(
        field: FocusedField,
        allowConversationFallback: Bool,
        allowClipboardFallback: Bool
    ) async -> ContextCapsule? {
        guard !secureInputEnabled(), field.role != AXRole.secureTextField else {
            clear()
            return nil
        }
        let priorDraft = current?.field.matchesRecommendationTarget(field) == true
            ? current?.snapshot.actionText ?? ""
            : ""
        async let snapshotRead = snapshotReader(field.appPID, field.appBundleID, allowClipboardFallback)
        async let conversationRead = conversationWithTimeout(pid: field.appPID, excludingDraft: priorDraft)
        guard let snapshot = await snapshotRead,
              snapshot.role != AXRole.secureTextField,
              !secureInputEnabled()
        else {
            clear()
            return nil
        }
        let freshConversation = await conversationRead
        let site = AppAdapterRegistry.siteLabel(bundleID: snapshot.appBundleID, windowTitle: snapshot.windowTitle)
        let matchingCurrent = current.flatMap { capsule in
            capsule.fingerprint.matchesIdentity(field: field, snapshot: snapshot, site: site)
                ? capsule
                : nil
        }
        let fallbackConversation: String? = {
            guard allowConversationFallback,
                  let matchingCurrent,
                  Date().timeIntervalSince(matchingCurrent.capturedAt) <= 5
            else { return nil }
            return matchingCurrent.conversation
        }()
        let conversation = freshConversation ?? fallbackConversation
        let capsule = ContextCapsule(
            field: field,
            snapshot: snapshot,
            conversation: conversation,
            site: site,
            signals: ContextSignalBuilder.build(snapshot: snapshot, conversationContext: conversation),
            fingerprint: TargetFingerprint.make(field: field, snapshot: snapshot, site: site),
            capturedAt: Date()
        )
        guard activeField == nil || activeField?.matchesRecommendationTarget(field) == true else { return nil }
        activeField = field
        current = capsule
        restartExpiry()
        return capsule
    }

    /// Returns on the deadline even if an app's AX tree walk is still draining
    /// on AXQueue. The late result is ignored and never delays the explicit run.
    private func conversationWithTimeout(pid: pid_t, excludingDraft: String) async -> String? {
        let gate = ConversationResultGate()
        return await withCheckedContinuation { continuation in
            Task {
                await gate.install(continuation)
                let value = await conversationReader(pid, excludingDraft)
                await gate.resolve(value)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await gate.resolve(nil)
            }
        }
    }
}
