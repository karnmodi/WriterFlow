import Foundation

/// Brief confirmation below the dock icon with a Restore action.
@MainActor
enum UndoToast {
    static func show(
        message: String,
        duration: TimeInterval = 2.0,
        belowIcon iconFrame: CGRect? = nil,
        onRestore: @escaping () -> Void
    ) {
        MessageToast.show(
            message,
            style: .success,
            duration: duration,
            belowIcon: iconFrame,
            action: MessageToast.Action(
                icon: "arrow.uturn.backward",
                label: "Restore original",
                handler: {
                    onRestore()
                    MessageToast.dismiss()
                }
            )
        )
    }

    static func dismiss() {
        MessageToast.dismiss()
    }
}
