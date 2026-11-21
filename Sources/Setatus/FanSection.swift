import SwiftUI

struct FanSection: View {
    @ObservedObject var fan: FanController
    @ObservedObject var metrics: MetricsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let current = metrics.fans.first {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        PanelLabel("Fan")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.0f", current.actual))
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundStyle(Bru.ink)
                                .monospacedDigit()
                            Text("RPM").font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Bru.ink)
                        }
                    }
                    Spacer()
                    Text(fan.running ? "MANUAL" : "AUTO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Bru.cardInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .slab(fan.running ? Bru.yellow : Bru.green)
                }
                BlockSlider(value: Binding(get: { fan.target },
                                           set: { fan.target = $0 }),
                            range: current.minimum...max(current.minimum + 1, current.maximum),
                            step: 50,
                            fill: fan.running ? Bru.yellow : Bru.green) { editing in
                    fan.editing = editing
                    if !editing { Task { await fan.apply(Int(fan.target)) } }
                }
                HStack {
                    fanFoot("MIN", current.minimum)
                    Spacer()
                    fanFoot("TARGET", current.target)
                    Spacer()
                    fanFoot("MAX", current.maximum)
                }
                if let message = fan.message {
                    Text(message).font(.system(size: 9)).foregroundStyle(Bru.muted)
                }
                if fan.running {
                    SlabButton("AUTO", fill: Bru.green, text: Bru.cardInk) {
                        Task { await fan.apply(0) }
                    }
                }
            } else {
                PanelLabel("Fan")
                Text("No fan detected").font(.system(size: 10)).foregroundStyle(Bru.muted)
            }
        }
        .card()
    }

    private func fanFoot(_ title: String, _ value: Double) -> some View {
        Text("\(title) \(Int(value.rounded()))")
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Bru.muted)
    }
}
