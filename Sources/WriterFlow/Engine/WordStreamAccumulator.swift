import Foundation

/// Smooths provider token fragments into word-sized UI updates without
/// changing the final byte sequence. A 30 ms flush prevents punctuation or a
/// long partial token from appearing stuck.
@MainActor
final class WordStreamAccumulator {
    private var buffer = ""
    private var flushTask: Task<Void, Never>?
    private let delay: Duration
    private let emit: (String) -> Void

    init(delay: Duration = .milliseconds(30), emit: @escaping (String) -> Void) {
        self.delay = delay
        self.emit = emit
    }

    func push(_ delta: String) {
        buffer += delta
        if let boundary = buffer.lastIndex(where: { $0.isWhitespace }) {
            let end = buffer.index(after: boundary)
            let complete = String(buffer[..<end])
            buffer = String(buffer[end...])
            if !complete.isEmpty { emit(complete) }
        }
        scheduleFlush()
    }

    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !buffer.isEmpty else { return }
        let remainder = buffer
        buffer = ""
        emit(remainder)
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        let delay = delay
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }
}
