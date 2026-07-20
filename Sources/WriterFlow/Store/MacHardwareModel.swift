import Foundation

/// A generic, non-identifying device label for pairing (Docs/contracts/
/// openapi.yaml `DeviceAuthorizeRequest.deviceLabel`: "Non-identifying
/// display label (e.g. \"MacBook Pro\"), not a hostname"). Deliberately does
/// NOT use `Host.current().localizedName` / `ProcessInfo.hostName` — on
/// macOS those are typically "<Owner's Name>'s MacBook Pro", which is
/// exactly what this field must not be.
enum MacHardwareModel {
    static var friendlyName: String {
        familyName(from: rawModelIdentifier())
    }

    private static func rawModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname("hw.model", &buffer, &size, nil, 0)
        guard result == 0 else { return "Mac" }
        return String(cString: buffer)
    }

    /// Maps a raw `hw.model` (e.g. "MacBookPro18,3") to a generic marketing
    /// family name. A short fixed table rather than an algorithmic split —
    /// Apple's own identifiers aren't consistently compound-worded (compare
    /// "MacBookPro" against "Macmini"), so guessing word boundaries produces
    /// wrong output ("Mac Book Pro"); this is a cosmetic label, not anything
    /// load-bearing, so a short table plus a safe fallback is the right
    /// amount of effort.
    private static func familyName(from raw: String) -> String {
        let table: [(prefix: String, name: String)] = [
            ("MacBookPro", "MacBook Pro"),
            ("MacBookAir", "MacBook Air"),
            ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"),
            ("MacPro", "Mac Pro"),
            ("iMac", "iMac"),
            ("Mac", "Mac")
        ]
        for entry in table where raw.hasPrefix(entry.prefix) {
            return entry.name
        }
        return "Mac"
    }
}
