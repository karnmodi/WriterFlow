import ApplicationServices
import CoreGraphics
import Foundation

/// Estimates caret screen position when AXBoundsForRange is unavailable (common in Notes/Gmail).
enum CaretEstimator {
    enum PlacementMode: Sendable {
        case besideCaret
        case fieldCorner
    }

    private struct VisualCaretMetrics {
        let visualLine: Int
        let visualColumn: Int
        let lineHeight: CGFloat
        let charWidth: CGFloat
    }

    private static let defaultLineHeight: CGFloat = 22
    private static let defaultCharWidth: CGFloat = 7
    private static let maxCaretWidth: CGFloat = 80
    private static let maxCaretHeight: CGFloat = 36

    static func anchorRect(
        for element: AXUIElement,
        cocoaFieldFrame: CGRect
    ) -> CGRect {
        let (rect, _) = placement(for: element, cocoaFieldFrame: cocoaFieldFrame)
        return rect
    }

    static func placement(
        for element: AXUIElement,
        cocoaFieldFrame: CGRect
    ) -> (CGRect, PlacementMode) {
        let textRange = AXCall.range(element, AXAttr.selectedTextRange)
            ?? NSRange(location: 0, length: 0)
        let caretIndex = textRange.location + (textRange.length > 0 ? textRange.length : 0)
        let text = AXCall.string(element, AXAttr.value) ?? ""
        let metrics = visualMetrics(text: text, caretUTF16: caretIndex, in: cocoaFieldFrame)

        for probe in caretProbes(caretIndex: caretIndex, textLength: (text as NSString).length) {
            if let axBounds = AXCall.boundsForRange(element, range: probe) {
                let cocoa = normalizeCaretBounds(AXCoords.toCocoa(axBounds))
                if isTightCaretBounds(cocoa, in: cocoaFieldFrame), isOnScreen(cocoa) {
                    return (cocoa, .besideCaret)
                }
                if isPlausibleCaretBounds(cocoa, in: cocoaFieldFrame), isOnScreen(cocoa) {
                    return (cocoa, .besideCaret)
                }
            }
        }

        let estimated = estimatedFromText(
            text: text,
            caretUTF16: caretIndex,
            in: cocoaFieldFrame,
            metrics: metrics
        )
        if isPlausibleCaretBounds(estimated, in: cocoaFieldFrame), isUsableFieldFrame(cocoaFieldFrame) {
            return (estimated, .besideCaret)
        }

        let fallback = topLeadingCaretAnchor(
            text: text,
            caretUTF16: caretIndex,
            in: cocoaFieldFrame,
            metrics: metrics
        )
        Log.focus.debug(
            "Caret fallback visualLine=\(metrics.visualLine, privacy: .public) col=\(metrics.visualColumn, privacy: .public)"
        )
        return (fallback, .fieldCorner)
    }

    static func fieldCornerAnchor(cocoaFieldFrame: CGRect) -> CGRect {
        topLeadingCaretAnchor(
            text: "",
            caretUTF16: 0,
            in: cocoaFieldFrame,
            metrics: visualMetrics(text: "", caretUTF16: 0, in: cocoaFieldFrame)
        )
    }

    private static func caretProbes(caretIndex: Int, textLength: Int) -> [NSRange] {
        var probes: [NSRange] = [NSRange(location: caretIndex, length: 0)]
        if caretIndex > 0 {
            probes.append(NSRange(location: caretIndex - 1, length: 1))
        }
        if caretIndex < textLength {
            probes.append(NSRange(location: caretIndex, length: 1))
        }
        return probes
    }

    private static func topLeadingCaretAnchor(
        text: String,
        caretUTF16: Int,
        in field: CGRect,
        metrics: VisualCaretMetrics
    ) -> CGRect {
        let estimated = estimatedFromText(
            text: text,
            caretUTF16: caretUTF16,
            in: field,
            metrics: metrics
        )
        if isOnScreen(estimated) { return estimated }

        let lineHeight = metrics.lineHeight
        return CGRect(
            x: field.minX + 12,
            y: field.maxY - lineHeight - 8,
            width: 4,
            height: lineHeight
        )
    }

    private static func normalizeCaretBounds(_ rect: CGRect) -> CGRect {
        var r = rect
        if r.width < 4 { r.size.width = 4 }
        if r.height < 8 { r.size.height = defaultLineHeight }
        if r.width > maxCaretWidth { r.size.width = 4 }
        if r.height > maxCaretHeight { r.size.height = defaultLineHeight }
        return r
    }

    private static func visualMetrics(
        text: String,
        caretUTF16: Int,
        in field: CGRect
    ) -> VisualCaretMetrics {
        let ns = text as NSString
        let clamped = max(0, min(caretUTF16, ns.length))
        let prefix = ns.substring(to: clamped) as NSString

        let logicalLines = prefix.length == 0 ? [""] : prefix.components(separatedBy: "\n")
        let lineIndex = max(0, logicalLines.count - 1)
        let colInLogicalLine = (logicalLines[lineIndex] as NSString).length

        // Fixed average glyph width — proportional UI fonts wrap around ~6–8pt.
        let charWidth = defaultCharWidth
        let charsPerLine = max(8, Int((field.width - 24) / charWidth))
        let visualLine = lineIndex + (colInLogicalLine / charsPerLine)
        let visualColumn = colInLogicalLine % charsPerLine

        let totalVisualLines = estimateTotalVisualLines(
            text: text,
            charsPerLine: charsPerLine
        )
        let lineHeight = min(
            defaultLineHeight,
            max(14, field.height / CGFloat(min(max(totalVisualLines, 1), 12)))
        )

        return VisualCaretMetrics(
            visualLine: visualLine,
            visualColumn: visualColumn,
            lineHeight: lineHeight,
            charWidth: charWidth
        )
    }

    private static func estimateTotalVisualLines(
        text: String,
        charsPerLine: Int
    ) -> Int {
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        return lines.reduce(0) { partial, line in
            let len = (line as NSString).length
            let wrapped = max(1, Int(ceil(Double(max(len, 1))) / Double(charsPerLine)))
            return partial + wrapped
        }
    }

    private static func estimatedFromText(
        text: String,
        caretUTF16: Int,
        in field: CGRect,
        metrics: VisualCaretMetrics
    ) -> CGRect {
        var x = field.minX + CGFloat(metrics.visualColumn) * metrics.charWidth + 12
        var y = field.maxY - CGFloat(metrics.visualLine + 1) * metrics.lineHeight - 4

        x = min(max(x, field.minX + 8), field.maxX - 20)
        y = min(max(y, field.minY + 8), field.maxY - metrics.lineHeight)

        return CGRect(x: x, y: y, width: 4, height: metrics.lineHeight)
    }

    private static func isTightCaretBounds(_ rect: CGRect, in field: CGRect) -> Bool {
        guard rect.width <= 30, rect.height >= 8, rect.height <= maxCaretHeight else { return false }
        guard rect.midY >= field.minY - 4, rect.midY <= field.maxY + 4 else { return false }
        guard rect.midX >= field.minX - 8, rect.midX <= field.maxX + 8 else { return false }
        return true
    }

    private static func isPlausibleCaretBounds(_ rect: CGRect, in field: CGRect) -> Bool {
        guard rect.height >= 8 && rect.maxX > 0 && rect.maxY > 0 else { return false }
        guard rect.height <= maxCaretHeight * 2, rect.width <= maxCaretWidth * 2 else { return false }

        if field.height > 24, rect.height > field.height * 0.45 { return false }
        if field.width > 40, rect.width > field.width * 0.65 { return false }

        let verticalCenter = rect.midY
        if verticalCenter < field.minY - 4 || verticalCenter > field.maxY + 4 { return false }

        return true
    }

    private static func isOnScreen(_ rect: CGRect) -> Bool {
        rect.maxX > 0 && rect.maxY > 0 && rect.height >= 8
    }

    static func isUsableFieldFrame(_ rect: CGRect) -> Bool {
        rect.width >= 40 && rect.height >= 16 && rect.maxX > 0 && rect.maxY > 0
    }
}
