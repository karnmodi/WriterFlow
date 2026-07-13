import AppKit
import SwiftUI

/// One flowing horizontal line with a gentle sine wave.
private struct WaveLineShape: Shape {
    var yFraction: CGFloat
    var wavePhase: CGFloat

    var animatableData: CGFloat {
        get { wavePhase }
        set { wavePhase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let y = h * yFraction
        let inset: CGFloat = w * 0.10
        let amplitude = h * 0.035
        let usable = w - inset * 2
        let steps = 12

        path.move(to: CGPoint(x: inset, y: y + sin(wavePhase) * amplitude))
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = inset + usable * t
            let phase = wavePhase + t * .pi * 1.6
            path.addLine(to: CGPoint(x: x, y: y + sin(phase) * amplitude))
        }
        return path
    }
}

/// Three wave lines — light gray fill with black border, readable on any background.
struct WaveLinesIconView: View {
    var size: CGFloat = 22
    var animated: Bool = true

    @State private var wavePhase: CGFloat = 0

    private static let fillColor = Color(white: 0.82)
    private static let borderColor = Color.black

    var body: some View {
        ZStack {
            waveLine(yFraction: 0.30, phaseOffset: 0)
            waveLine(yFraction: 0.50, phaseOffset: 1.1)
            waveLine(yFraction: 0.70, phaseOffset: 2.2)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
        }
    }

    private func waveLine(yFraction: CGFloat, phaseOffset: CGFloat) -> some View {
        let shape = WaveLineShape(yFraction: yFraction, wavePhase: wavePhase + phaseOffset)
        let borderWidth = max(1.0, size * 0.038)
        let fillWidth = max(1.5, size * 0.072)
        let outerWidth = fillWidth + borderWidth * 2

        return ZStack {
            shape.stroke(
                Self.borderColor,
                style: StrokeStyle(lineWidth: outerWidth, lineCap: .round, lineJoin: .round)
            )
            shape.stroke(
                Self.fillColor,
                style: StrokeStyle(lineWidth: fillWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

enum WriterFlowIcon {
    @MainActor
    static func makeNSImage(size: CGFloat = 16) -> NSImage? {
        let renderer = ImageRenderer(content: WaveLinesIconView(size: size, animated: false))
        renderer.scale = 2
        return renderer.nsImage
    }
}
