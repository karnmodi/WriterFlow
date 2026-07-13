import Foundation

/// Brief non-activating error/info banner — does not steal focus from the text field.
@MainActor
enum ErrorToast {
    static func show(
        _ message: String,
        duration: TimeInterval = 3.0,
        belowIcon iconFrame: CGRect? = nil,
        style: ToastStyle = .error
    ) {
        MessageToast.show(message, style: style, duration: duration, belowIcon: iconFrame)
    }

    static func dismiss() {
        MessageToast.dismiss()
    }
}
