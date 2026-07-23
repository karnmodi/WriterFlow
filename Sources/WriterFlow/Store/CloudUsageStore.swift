import Foundation

/// Metadata-only projection from SSE `usage.summary`; never stores draft or output content.
@MainActor
final class CloudUsageStore: ObservableObject {
    static let shared = CloudUsageStore()

    @Published private(set) var usedUnits: Int?
    @Published private(set) var remainingUnits: Int?

    private init() {}

    func update(usedUnits: Int, remainingUnits: Int) {
        self.usedUnits = usedUnits
        self.remainingUnits = remainingUnits
    }
}
