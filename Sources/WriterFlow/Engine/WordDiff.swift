import Foundation

/// Word-level diff for highlighting Fix Grammar changes in the preview card.
enum WordDiff {
    struct Segment: Identifiable {
        let id = UUID()
        let text: String
        let changed: Bool
    }

    /// Splits `old`/`new` into whitespace-separated words and marks the words
    /// in `new` that were inserted or changed relative to `old`.
    static func segments(from old: String, to new: String) -> [Segment] {
        let oldWords = old.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let newWords = new.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        let diff = newWords.difference(from: oldWords)
        var insertedIndices = Set<Int>()
        for change in diff {
            if case .insert(let offset, _, _) = change {
                insertedIndices.insert(offset)
            }
        }

        return newWords.enumerated().map { index, word in
            Segment(text: word, changed: insertedIndices.contains(index))
        }
    }
}
