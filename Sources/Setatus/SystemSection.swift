import SwiftUI

struct SystemSection: View {
    @ObservedObject var metrics: MetricsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PanelLabel("System")
                Spacer()
                Text(temperature("CPU").map { "SMC · \($0)" } ?? "—")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Bru.muted)
            }
            HStack(spacing: 8) {
                tile("CPU",
                     value: String(format: "%.0f%%", metrics.cpu),
                     detail: temperature("CPU"),
                     ratio: metrics.cpu / 100,
                     fill: Bru.paper,
                     text: Bru.ink)
                tile("GPU",
                     value: metrics.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "—",
                     detail: temperature("GPU"),
                     ratio: (metrics.gpuUsage ?? 0) / 100,
                     fill: Bru.blue,
                     text: .white)
                tile("RAM",
                     value: String(format: "%.0f%%", metrics.ramPercent),
                     detail: "\(Fmt.memory(metrics.ramUsed)) / \(Fmt.memory(metrics.ramTotal))",
                     ratio: metrics.ramPercent / 100,
                     fill: Bru.yellow,
                     text: Bru.cardInk)
            }
            infoRow("Power", powerText)
            infoRow("Uptime", uptimeText)
        }
    }

    private func tile(_ title: String, value: String, detail: String?,
                      ratio: Double, fill: Color, text: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelLabel(title, text)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .foregroundStyle(text)
                .monospacedDigit()
            Text(detail ?? "—")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(fill == Bru.blue ? Color.white.opacity(0.8) : Bru.muted)
                .lineLimit(1)
            BlockMeter(value: ratio, segments: 6, color: text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(
            ZStack {
                Rectangle().fill(Bru.ink).offset(x: 4, y: 4)
                Rectangle().fill(fill)
            }
        )
        .overlay(Rectangle().stroke(Bru.ink, lineWidth: 3))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            PanelLabel(title)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func temperature(_ name: String) -> String? {
        metrics.temps.first { $0.label == name }.map { String(format: "%.0f °C", $0.celsius) }
    }

    private var uptimeText: String {
        var parts = [Fmt.duration(metrics.uptime)]
        let known: Set<String> = ["CPU", "GPU"]
        parts += metrics.temps.filter { !known.contains($0.label) }.prefix(2)
            .map { String(format: "%@ %.0f°C", $0.label, $0.celsius) }
        return parts.joined(separator: " · ")
    }

    private var powerText: String {
        guard let power = metrics.power else { return "—" }
        var parts: [String] = []
        if let input = power.inputWatts { parts.append(Fmt.watts(input)) }
        if let adapter = power.adapterWatts { parts.append(String(format: "%.0f W adapter", adapter)) }
        if let percent = power.batteryPercent {
            parts.append(String(format: "%.0f%%", percent) + (power.charging ? " charging" : ""))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
