import CoreGraphics
import CryptoKit
import Foundation

/// Local target identity used to reject stale generation/apply operations.
/// The content revision is opaque and is never logged with source text.
struct TargetFingerprint: Sendable, Equatable {
    let appPID: pid_t
    let bundleID: String?
    let role: String
    let subrole: String?
    let windowIdentity: String?
    let site: String?
    let elementIdentifier: String?
    let quantizedFrame: CGRect
    let selectedRange: NSRange
    let contentRevision: String

    static func make(field: FocusedField, snapshot: FieldSnapshot, site: String?) -> TargetFingerprint {
        TargetFingerprint(
            appPID: field.appPID,
            bundleID: field.appBundleID,
            role: snapshot.role,
            subrole: snapshot.subrole,
            windowIdentity: snapshot.windowTitle,
            site: site,
            elementIdentifier: snapshot.elementIdentifier,
            quantizedFrame: quantize(field.frame),
            selectedRange: snapshot.selectedRange,
            contentRevision: contentRevision(snapshot: snapshot)
        )
    }

    static func contentRevision(snapshot: FieldSnapshot) -> String {
        let material = [
            snapshot.role,
            snapshot.subrole ?? "",
            snapshot.elementIdentifier ?? "",
            snapshot.fullText,
            snapshot.selectedText,
            "\(snapshot.selectedRange.location):\(snapshot.selectedRange.length)"
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    func matches(field: FocusedField, snapshot: FieldSnapshot, site currentSite: String?) -> Bool {
        matchesIdentity(field: field, snapshot: snapshot, site: currentSite)
            && selectedRange == snapshot.selectedRange
            && contentRevision == Self.contentRevision(snapshot: snapshot)
    }

    func matchesIdentity(field: FocusedField, snapshot: FieldSnapshot, site currentSite: String?) -> Bool {
        appPID == field.appPID
            && bundleID == field.appBundleID
            && role == snapshot.role
            && subrole == snapshot.subrole
            && windowIdentity == snapshot.windowTitle
            && site == currentSite
            && elementIdentifier == snapshot.elementIdentifier
            && quantizedFrame == Self.quantize(field.frame)
    }

    private static func quantize(_ frame: CGRect) -> CGRect {
        CGRect(
            x: (frame.origin.x / 4).rounded() * 4,
            y: (frame.origin.y / 4).rounded() * 4,
            width: (frame.width / 4).rounded() * 4,
            height: (frame.height / 4).rounded() * 4
        )
    }
}
