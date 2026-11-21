import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(usage: model.usage)
            LimitsSection(usage: model.usage)
            SystemSection(metrics: model.metricsStore)
            FanSection(fan: model.fan, metrics: model.metricsStore)
            ChargeSection(charge: model.charge)
            NetworkSection(metrics: model.metricsStore)
            ActivitySection(processes: model.processes, ports: model.ports)
        }
        .padding(12)
        .frame(width: 356)
        .background(Rectangle().fill(Bru.cream))
        .onAppear {
            model.ports.refresh()
        }
    }
}

private struct PanelHeader: View {
    @ObservedObject var usage: UsageStore

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Bru.yellow)
                .overlay(Rectangle().stroke(Bru.ink, lineWidth: 2))
                .frame(width: 10, height: 10)
            Text("SETATUS")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Bru.ink)
            Spacer()
            Text(usage.updatedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.muted)
            Button {
                Task { await usage.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Bru.cardInk)
                    .frame(width: 26, height: 26)
                    .slab(Bru.yellow, shadow: 3)
            }
            .buttonStyle(.plain)
            .help("Refresh usage")
            .accessibilityLabel("Refresh usage")
        }
    }
}
