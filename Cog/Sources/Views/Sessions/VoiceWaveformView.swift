import SwiftUI

struct VoiceWaveformView: View {
    var barCount = 5
    var color: Color = .red
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 3
    var maxHeight: CGFloat = 16

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let offset = Double(index) * 0.45
                    let scale = 0.2 + 0.8 * abs(sin(t * 3.0 + offset))
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(color)
                        .frame(width: barWidth, height: maxHeight * scale)
                }
            }
            .frame(height: maxHeight)
        }
    }
}
