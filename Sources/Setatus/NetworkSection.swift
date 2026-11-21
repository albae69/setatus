import SwiftUI

struct NetworkSection: View {
    @ObservedObject var metrics: MetricsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PanelLabel("Internet")
                Spacer()
                SlabButton(metrics.speedTesting ? "TESTING…" : "SPEED TEST",
                           fill: Bru.ink, text: Bru.onInk) {
                    Task { await metrics.runSpeedTest() }
                }
                .disabled(metrics.speedTesting)
            }
            HStack(spacing: 12) {
                flow("↓", title: "Download", value: "\(Fmt.rate(metrics.netDown))/s")
                flow("↑", title: "Upload", value: "\(Fmt.rate(metrics.netUp))/s")
            }
            HStack {
                Text("\(Fmt.bytes(metrics.netTotalIn)) IN · \(Fmt.bytes(metrics.netTotalOut)) OUT")
                Spacer()
                Text(metrics.localIP ?? "—")
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Bru.muted)

            HStack(spacing: 6) {
                Spacer(minLength: 4)
                if let speed = metrics.speedTest {
                    Text("↓ \(String(format: "%.1f", speed.down)) · ↑ \(String(format: "%.1f", speed.up)) Mbps")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Bru.ink)
                } else if let error = metrics.speedTestError {
                    Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
                }
            }
        }
        .card()
    }

    private func flow(_ arrow: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            PanelLabel("\(arrow) \(title)")
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
