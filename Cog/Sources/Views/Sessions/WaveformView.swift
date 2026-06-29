import SwiftUI

struct WaveformView: View {
    var audioLevel: Float
    var barCount: Int = 5

    @State private var phases: [Double] = []

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    audioLevel: audioLevel,
                    phase: phases.indices.contains(index) ? phases[index] : 0
                )
            }
        }
        .onAppear {
            phases = (0..<barCount).map { i in
                Double(i) * .pi / Double(barCount)
            }
        }
    }
}

private struct WaveformBar: View {
    var audioLevel: Float
    var phase: Double

    @State private var animating = false

    private var minHeight: CGFloat { 4 }
    private var maxHeight: CGFloat { 20 }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.red)
            .frame(width: 3, height: barHeight)
            .animation(.easeInOut(duration: 0.15), value: audioLevel)
            .modifier(IdlePulse(active: audioLevel < 0.05, phase: phase))
    }

    private var barHeight: CGFloat {
        let level = CGFloat(audioLevel)
        let range = maxHeight - minHeight
        return minHeight + range * level
    }
}

private struct IdlePulse: ViewModifier {
    var active: Bool
    var phase: Double

    func body(content: Content) -> some View {
        if active {
            content
                .phaseAnimator([false, true]) { view, value in
                    view.scaleEffect(
                        y: value ? 1.0 + 0.5 * sin(phase) : 1.0 + 0.5 * cos(phase),
                        anchor: .center
                    )
                } animation: { _ in
                    .easeInOut(duration: 0.6)
                }
        } else {
            content
        }
    }
}
