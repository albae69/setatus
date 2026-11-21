import SwiftUI

struct BlockMeter: View {
    let value: Double
    var segments: Int = 12
    var color: Color = Bru.ink

    var body: some View {
        let filled = Int((min(max(value, 0), 1) * Double(segments)).rounded())
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? color : Bru.paper)
                    .overlay(Rectangle().stroke(Bru.ink, lineWidth: 1.5))
                    .frame(height: 10)
            }
        }
        .frame(height: 10)
    }
}

struct BlockSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var fill: Color = Bru.yellow
    var onEdit: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let ratio = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Rectangle().fill(Bru.paper)
                    .overlay(Rectangle().stroke(Bru.ink, lineWidth: 2))
                    .frame(height: 8)
                Rectangle().fill(fill)
                    .frame(width: width * min(max(ratio, 0), 1), height: 8)
                Rectangle().fill(fill)
                    .overlay(Rectangle().stroke(Bru.ink, lineWidth: 2))
                    .frame(width: 16, height: 20)
                    .offset(x: min(max(width * ratio - 9, 0), width - 18))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    onEdit(true)
                    set(to: gesture.location.x / width)
                }
                .onEnded { _ in onEdit(false) })
        }
        .frame(height: 20)
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            value = min(max(value + delta, range.lowerBound), range.upperBound)
            onEdit(false)
        }
    }

    private func set(to ratio: CGFloat) {
        let clamped = min(max(ratio, 0), 1)
        let raw = range.lowerBound + Double(clamped) * (range.upperBound - range.lowerBound)
        value = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
    }
}

struct PanelLabel: View {
    private let text: String
    private let color: Color

    init(_ text: String, _ color: Color = Bru.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(color)
    }
}

struct SlabButton: View {
    private let title: String
    private let fill: Color
    private let text: Color
    private let shadow: CGFloat
    private let action: () -> Void

    init(_ title: String, fill: Color, text: Color, shadow: CGFloat = 2, action: @escaping () -> Void) {
        self.title = title
        self.fill = fill
        self.text = text
        self.shadow = shadow
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(text)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .slab(fill, shadow: shadow)
        }
        .buttonStyle(.plain)
    }
}
