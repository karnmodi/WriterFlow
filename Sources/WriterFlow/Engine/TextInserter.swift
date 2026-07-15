import AppKit
import ApplicationServices
import Foundation

/// Unified text-replacement pipeline: AX write with verification, then clipboard paste.
enum TextInserter {
    private struct WriteContext: Sendable {
        let pid: pid_t
        let bundleID: String?
        let role: String
        let range: NSRange
        let replacingAll: Bool
        let preText: String
        let isWeb: Bool
    }

    static func replace(
        pid: pid_t,
        range: NSRange,
        with replacement: String,
        bundleID: String? = nil,
        site: String? = nil,
        role: String? = nil
    ) async -> WriteResult {
        let context = await readContext(pid: pid, range: range, role: role, bundleID: bundleID)

        guard let context else {
            recordWrite(bundleID, ok: false)
            return .failed("No focused element")
        }

        let clipboardMode = await MainActor.run {
            AppRuleStore.shared.rule(forBundleID: bundleID, site: site)?.clipboardFallback
                ?? (SettingsStore.shared.forceClipboardFallback ? true : nil)
        }

        if !context.isWeb && clipboardMode != true {
            if let result = await trySelectedTextReplace(context: context, replacement: replacement) {
                recordWrite(context.bundleID, ok: true)
                return result
            }
            if let result = await tryFullValueReplace(context: context, replacement: replacement) {
                recordWrite(context.bundleID, ok: true)
                return result
            }
        }

        guard clipboardMode != false else {
            recordWrite(context.bundleID, ok: false)
            return .failed("AX write failed and clipboard paste is disabled for this app.")
        }

        let injected = await MainActor.run {
            ClipboardWriter.executePaste(
                pid: context.pid,
                range: context.range,
                replacement: replacement,
                replacingAll: context.replacingAll,
                role: context.role,
                preText: context.preText,
                isWeb: context.isWeb
            )
        }

        guard injected else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(replacement, forType: .string)
            recordWrite(context.bundleID, ok: false)
            return .failed("Couldn't inject paste — text is on your clipboard. Press ⌘V.")
        }

        try? await Task.sleep(nanoseconds: 120_000_000)

        let verified = await verifyWrite(
            pid: context.pid,
            replacement: replacement,
            preText: context.preText
        )

        if verified {
            Log.engine.info("Clipboard tier verified for pid=\(context.pid, privacy: .public)")
            recordWrite(context.bundleID, ok: true)
            return .clipboardPasted
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(replacement, forType: .string)
        recordWrite(context.bundleID, ok: false)
        Log.engine.error("Clipboard tier failed verification pid=\(context.pid, privacy: .public)")
        return .failed("Paste didn't land — text is on your clipboard. Press ⌘V.")
    }

    // MARK: - Context

    private static func readContext(
        pid: pid_t,
        range: NSRange,
        role: String?,
        bundleID: String?
    ) async -> WriteContext? {
        await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                continuation.resume(returning: readContextSync(
                    pid: pid,
                    range: range,
                    role: role,
                    bundleID: bundleID
                ))
            }
        }
    }

    private static func readContextSync(
        pid: pid_t,
        range: NSRange,
        role: String?,
        bundleID: String?
    ) -> WriteContext? {
        let app = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(app)
        guard let rawFocused = FocusedElementResolver.focusedElement(in: app),
              let focused = FocusedElementResolver.resolveEditable(from: rawFocused)
        else { return nil }

        let resolvedRole = role ?? AXCall.string(focused, AXAttr.role) ?? ""
        let currentText = AXCall.string(focused, AXAttr.value) ?? ""
        let textLength = (currentText as NSString).length
        let replacingAll = range.location == 0 && range.length >= textLength && textLength > 0

        return WriteContext(
            pid: pid,
            bundleID: bundleID,
            role: resolvedRole,
            range: range,
            replacingAll: replacingAll,
            preText: currentText,
            isWeb: resolvedRole == AXRole.webArea
        )
    }

    // MARK: - AX tiers

    private static func trySelectedTextReplace(
        context: WriteContext,
        replacement: String
    ) async -> WriteResult? {
        let wrote = await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                continuation.resume(returning: attemptSelectedTextReplace(
                    pid: context.pid,
                    range: context.range,
                    replacement: replacement
                ))
            }
        }
        guard wrote else { return nil }

        try? await Task.sleep(nanoseconds: 50_000_000)
        let verified = await verifyWrite(
            pid: context.pid,
            replacement: replacement,
            preText: context.preText
        )
        guard verified else {
            Log.engine.info("AX selectedText tier unverified — falling through")
            return nil
        }
        Log.engine.info("AX selectedText tier verified")
        return .selectedTextReplaced
    }

    private static func tryFullValueReplace(
        context: WriteContext,
        replacement: String
    ) async -> WriteResult? {
        let wrote = await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                continuation.resume(returning: attemptFullValueReplace(
                    pid: context.pid,
                    range: context.range,
                    role: context.role,
                    replacement: replacement
                ))
            }
        }
        guard wrote else { return nil }

        try? await Task.sleep(nanoseconds: 50_000_000)
        let verified = await verifyWrite(
            pid: context.pid,
            replacement: replacement,
            preText: context.preText
        )
        guard verified else {
            Log.engine.info("AX fullValue tier unverified — falling through")
            return nil
        }
        Log.engine.info("AX fullValue tier verified")
        return .fullValueReplaced
    }

    private static func attemptSelectedTextReplace(
        pid: pid_t,
        range: NSRange,
        replacement: String
    ) -> Bool {
        guard let focused = resolveFocused(pid: pid) else { return false }
        return AXCall.setRange(focused, AXAttr.selectedTextRange, range: range)
            && AXCall.setString(focused, AXAttr.selectedText, value: replacement)
    }

    private static func attemptFullValueReplace(
        pid: pid_t,
        range: NSRange,
        role: String,
        replacement: String
    ) -> Bool {
        guard let focused = resolveFocused(pid: pid) else { return false }

        let plainRoles: Set<String> = [
            AXRole.textField,
            AXRole.textArea,
            AXRole.comboBox
        ]
        guard plainRoles.contains(role) || AXCall.isSettable(focused, AXAttr.value) else {
            return false
        }

        let currentText = AXCall.string(focused, AXAttr.value) ?? ""
        let textLength = (currentText as NSString).length
        let safeRange = clampRange(range, in: textLength)
        let newText = (currentText as NSString).replacingCharacters(in: safeRange, with: replacement)
        return AXCall.setString(focused, AXAttr.value, value: newText)
    }

    // MARK: - Verification

    private static func verifyWrite(
        pid: pid_t,
        replacement: String,
        preText: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            AXQueue.shared.async {
                continuation.resume(returning: verifyWriteSync(
                    pid: pid,
                    replacement: replacement,
                    preText: preText
                ))
            }
        }
    }

    private static func verifyWriteSync(
        pid: pid_t,
        replacement: String,
        preText: String
    ) -> Bool {
        guard let focused = resolveFocused(pid: pid) else { return false }
        let postText = AXCall.string(focused, AXAttr.value) ?? ""

        if !replacement.isEmpty, postText.contains(replacement + replacement) {
            Log.engine.error("verifyWrite: duplicated replacement detected")
            return false
        }

        if postText.contains(replacement) { return true }

        let trimmedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReplacement.isEmpty, postText.contains(trimmedReplacement) { return true }

        return postText != preText && !postText.isEmpty
    }

    // MARK: - Helpers

    private static func resolveFocused(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXCall.armTimeout(app)
        guard let raw = FocusedElementResolver.focusedElement(in: app) else { return nil }
        return FocusedElementResolver.resolveEditable(from: raw)
    }

    private static func clampRange(_ range: NSRange, in length: Int) -> NSRange {
        let location = max(0, min(range.location, length))
        let remaining = length - location
        return NSRange(location: location, length: max(0, min(range.length, remaining)))
    }

    private static func recordWrite(_ bundleID: String?, ok: Bool) {
        Task { await CompatibilityMap.shared.recordWrite(bundleID: bundleID, ok: ok) }
    }
}
