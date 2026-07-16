import Foundation

/// Three parallel rewrite options shown in the overlay preview card.
struct PreviewVariants: Sendable, Equatable {
    static let count = 3

    var texts: [String]
    var selectedIndex: Int
    var completedIndices: Set<Int>

    init(
        texts: [String] = Array(repeating: "", count: count),
        selectedIndex: Int = 0,
        completedIndices: Set<Int> = []
    ) {
        self.texts = texts.count == Self.count
            ? texts
            : Array(repeating: "", count: Self.count)
        self.selectedIndex = min(max(selectedIndex, 0), Self.count - 1)
        self.completedIndices = completedIndices
    }

    var selectedText: String {
        texts[selectedIndex]
    }

    var isStreaming: Bool {
        completedIndices.count < Self.count
    }

    var canReplace: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func empty() -> PreviewVariants {
        PreviewVariants()
    }

    static func single(_ text: String) -> PreviewVariants {
        var variants = PreviewVariants()
        variants.texts[0] = text
        // A single-output action has no background variant streams left to finish.
        variants.completedIndices = Set(0..<Self.count)
        return variants
    }

    mutating func append(to index: Int, delta: String) {
        guard texts.indices.contains(index) else { return }
        texts[index] += delta
    }

    mutating func markCompleted(_ index: Int) {
        guard texts.indices.contains(index) else { return }
        completedIndices.insert(index)
    }

    mutating func select(_ index: Int) {
        guard texts.indices.contains(index) else { return }
        selectedIndex = index
    }
}

extension WritingAction {
    /// V1 makes one provider request per explicit action. The variant container remains
    /// for preview compatibility, but parallel generation is disabled to avoid silently
    /// tripling the user's Azure usage and cost.
    var usesMultiVariantPreview: Bool {
        false
    }
}
