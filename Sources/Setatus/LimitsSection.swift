import SwiftUI

struct LimitsSection: View {
    @ObservedObject var usage: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if let current = usage.data.value {
                    HStack(alignment: .top) {
                        PanelLabel("OpenCode · 5 hours", Bru.cardInk)
                        Spacer()
                        Text(current.rolling.resetsAt.map { "resets \(Fmt.countdown($0))" } ?? "—")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.cardInk)
                    }
                    HStack(alignment: .center, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.0f", current.rolling.percent))
                                .font(.system(size: 32, weight: .bold, design: .monospaced))
                                .foregroundStyle(Bru.cardInk)
                            Text("%").font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(Bru.cardInk)
                        }
                        Spacer(minLength: 0)
                        if let today = usage.today {
                            usageGrid(today)
                        }
                    }
                    BlockMeter(value: current.rolling.percent / 100, color: Bru.cardInk)
                } else if let error = usage.data.error {
                    PanelLabel("OpenCode · 5 hours", Bru.cardInk)
                    Text(error).font(.system(size: 10)).foregroundStyle(Bru.cardInk)
                } else {
                    PanelLabel("OpenCode · 5 hours", Bru.cardInk)
                    Text("Loading…").font(.system(size: 10)).foregroundStyle(Bru.cardInk)
                }
                if let error = usage.data.error, usage.data.value != nil {
                    Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
                }
            }
            .card(Bru.yellow)

            HStack(spacing: 10) {
                windowCard("Week", usage.data.value?.weekly)
                windowCard("Month", usage.data.value?.monthly)
            }
        }
    }

    private func windowCard(_ title: String, _ window: LimitWindow?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                PanelLabel(title)
                Spacer()
                Text(String(format: "%.0f%%", window?.percent ?? 0))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Bru.ink)
            }
            BlockMeter(value: (window?.percent ?? 0) / 100, segments: 6,
                       color: (window?.percent ?? 0) > 60 ? Bru.red : Bru.ink)
            Text(window?.resetsAt.map { "resets \(Fmt.countdown($0))" } ?? "—")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(shadow: 4)
    }

    private func usageGrid(_ today: TodayStats) -> some View {
        let hit = today.promptTokens > 0
            ? String(format: "%.0f%%", Double(today.cacheReadTokens) / Double(today.promptTokens) * 100)
            : "—"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                usageStat("Req", "\(today.requests)")
                usageStat("In", Fmt.compact(today.inputTokens))
                usageStat("Out", Fmt.compact(today.completionTokens))
                usageStat("Total", Fmt.compact(today.promptTokens + today.completionTokens))
            }
            HStack(spacing: 6) {
                usageStat("Cache R", Fmt.compact(today.cacheReadTokens))
                usageStat("Cache W", Fmt.compact(today.cacheWriteTokens))
                usageStat("Hit", hit)
                usageStat("Cost", String(format: "$%.2f", today.cost))
            }
        }
    }

    private func usageStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(Bru.cardInk.opacity(0.65))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.cardInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 50, alignment: .leading)
    }
}
