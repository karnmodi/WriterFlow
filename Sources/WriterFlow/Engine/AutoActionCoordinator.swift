import Foundation

/// Owns one explicit-trigger auto/adjust operation. Local context may be warm,
/// but constructing and sending the inference request happens only here.
@MainActor
final class AutoActionCoordinator {
    private let capsules: ContextCapsuleStore
    private let engine: ActionEngine
    private unowned let overlay: OverlayController
    private var captureTask: Task<Void, Never>?

    init(capsules: ContextCapsuleStore, engine: ActionEngine, overlay: OverlayController) {
        self.capsules = capsules
        self.engine = engine
        self.overlay = overlay
    }

    func trigger(field: FocusedField, directive: String? = nil) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self, let capsule = await capsules.captureForTrigger(field: field) else {
                ErrorToast.show("Couldn't read the active writing field. Try again.")
                return
            }
            guard !Task.isCancelled else { return }
            let request = InferenceRequestBuilder.auto(capsule: capsule, directive: directive)
            overlay.prepareAutoRun(
                field: field,
                operationID: request.operationId,
                fingerprint: capsule.fingerprint,
                directive: directive
            )
            engine.runAuto(request: request, capsule: capsule)
        }
    }

    func retry(field: FocusedField, directive: String?, retryOf: UUID?) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            guard let capsule = await capsules.captureForTrigger(field: field) else {
                overlay.failPreview(message: "Couldn't re-read the active writing field. The previous result is still available.")
                return
            }
            guard !Task.isCancelled else { return }
            let request = InferenceRequestBuilder.auto(
                capsule: capsule,
                directive: directive,
                retryOf: retryOf
            )
            overlay.prepareAutoRetry(
                field: field,
                operationID: request.operationId,
                retryOf: retryOf,
                fingerprint: capsule.fingerprint,
                directive: directive
            )
            engine.runAuto(request: request, capsule: capsule)
        }
    }

    func adjust(
        instruction: String,
        field: FocusedField,
        parentOperationID: UUID,
        priorOutput: String
    ) {
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self, let capsule = await capsules.captureForTrigger(field: field) else {
                ErrorToast.show("Couldn't revalidate the active writing field. Try again.")
                return
            }
            guard !Task.isCancelled else { return }
            let request = InferenceRequestBuilder.adjust(
                capsule: capsule,
                parentOperationId: parentOperationID,
                instruction: instruction,
                priorOutput: priorOutput
            )
            overlay.prepareAdjustment(
                operationID: request.operationId,
                fingerprint: capsule.fingerprint,
                parentOperationID: parentOperationID,
                instruction: instruction,
                priorOutput: priorOutput
            )
            engine.runAuto(request: request, capsule: capsule)
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        engine.cancel()
    }
}
