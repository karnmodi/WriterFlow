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

/// Three parallel wave lines — neutral, clearly visible, gently animated.
struct WaveLinesIconView: View {
    var size: CGFloat = 22
    var animated: Bool = true

    @State private var wavePhase: CGFloat = 0
    @State private var shadowOpacity: Double = 0.18

    private var lineColor: Color {
        Color.primary.opacity(0.78)
    }

    var body: some View {
        ZStack {
            waveLine(yFraction: 0.30, phaseOffset: 0)
            waveLine(yFraction: 0.50, phaseOffset: 1.1)
            waveLine(yFraction: 0.70, phaseOffset: 2.2)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(shadowOpacity), radius: size * 0.14, y: 1)
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                shadowOpacity = 0.38
            }
        }
    }

    private func waveLine(yFraction: CGFloat, phaseOffset: CGFloat) -> some View {
        WaveLineShape(yFraction: yFraction, wavePhase: wavePhase + phaseOffset)
            .stroke(
                lineColor,
                style: StrokeStyle(
                    lineWidth: max(1.4, size * 0.075),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
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
