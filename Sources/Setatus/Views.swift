import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: Model
    @State private var keyText = ""
    @State private var editingKey = false
    @State private var confirmPID: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            limitsSection
            Divider()
            systemSection
            fanSection
            Divider()
            netSection
            Divider()
            processSection
            Divider()
            keySection
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            Task { keyText = await Task.detached { UsageService.apiKey() }.value ?? "" }
        }
    }

    private var header: some View {
        HStack {
            Text("Setatus").font(.headline)
            Spacer()
            Button {
                Task { await model.refreshUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh usage")
            .accessibilityLabel("Refresh usage")
        }
    }

    private var systemSection: some View {
        VStack(spacing: 8) {
            row(title: "CPU", value: withTemp(String(format: "%.0f%%", model.cpu), "CPU"), ratio: model.cpu / 100)
            row(title: "GPU",
                value: withTemp(model.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "—", "GPU"),
                ratio: (model.gpuUsage ?? 0) / 100)
            row(title: "RAM",
                value: String(format: "%.0f%%", model.ramPercent),
                ratio: model.ramPercent / 100)
            row(title: "Power", value: powerText, ratio: 0, showsBar: false)
            row(title: "Uptime", value: Fmt.duration(model.uptime), ratio: 0, showsBar: false)
            if let extras = extraTemps {
                Text(extras).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var powerText: String {
        guard let power = model.power else { return "—" }
        var parts: [String] = []
        if let input = power.inputWatts { parts.append(Fmt.watts(input) + " in") }
        if let adapter = power.adapterWatts { parts.append(String(format: "%.0f W adapter", adapter)) }
        if let percent = power.batteryPercent {
            parts.append(String(format: "%.0f%%", percent) + (power.charging ? " charging" : ""))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func withTemp(_ value: String, _ label: String) -> String {
        guard let temp = model.temps.first(where: { $0.label == label }) else { return value }
        return value + String(format: " · %.0f °C", temp.celsius)
    }

    private var extraTemps: String? {
        let known: Set<String> = ["CPU", "GPU"]
        let rest = model.temps.filter { !known.contains($0.label) }.prefix(3)
        guard !rest.isEmpty else { return nil }
        return rest.map { String(format: "%@ %.0f°C", $0.label, $0.celsius) }.joined(separator: " · ")
    }

    private var netSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Internet").font(.caption).foregroundStyle(.secondary)
            flowRow(arrow: "↓", label: "Download", value: "\(Fmt.rate(model.netDown))/s")
            flowRow(arrow: "↑", label: "Upload", value: "\(Fmt.rate(model.netUp))/s")
            HStack {
                Text("Total ↓ \(bytes(model.netTotalIn))   ↑ \(bytes(model.netTotalOut))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                Text("IP \(model.localIP ?? "—")")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func flowRow(arrow: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(arrow).frame(width: 10, alignment: .center)
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    @ViewBuilder
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OpenCode limits").font(.caption).foregroundStyle(.secondary)
            if let usage = model.usage {
                limitRow("5 hours", usage.rolling)
                limitRow("Week", usage.weekly)
                limitRow("Month", usage.monthly)
            } else if let error = model.usageError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.usageError, model.usage != nil {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
            if let today = model.today {
                Text("Today  \(today.requests) req · \(compact(today.promptTokens + today.completionTokens)) tok · $\(String(format: "%.3f", today.cost))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fanSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fan").font(.caption).foregroundStyle(.secondary)
            if let fan = model.fans.first {
                HStack {
                    Text("\(Int(fan.actual.rounded())) rpm")
                        .font(.caption).monospacedDigit()
                    Spacer()
                    Text(model.fanRunning ? "manual" : "auto")
                        .font(.caption2)
                        .foregroundStyle(model.fanRunning ? .orange : .secondary)
                }
                Slider(value: Binding(get: { model.fanTarget },
                                      set: { model.fanTarget = $0 }),
                       in: fan.minimum...max(fan.minimum + 1, fan.maximum),
                       step: 50) { editing in
                    model.fanEditing = editing
                    if !editing { Task { await model.applyFan(Int(model.fanTarget)) } }
                }
                HStack {
                    Text("min \(Int(fan.minimum.rounded())) · max \(Int(fan.maximum.rounded())) · target \(Int(fan.target.rounded()))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Auto") { Task { await model.applyFan(0) } }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
                if let message = model.fanMessage {
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("No fan detected").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Processes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.refreshProcesses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .help("Refresh processes")
                .accessibilityLabel("Refresh processes")
            }

            ForEach(model.processes) { row in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(row.pid) · \(String(format: "%.1f%%", row.cpu)) · \(String(format: "%.0f MB", row.memoryMB))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if confirmPID == row.pid {
                        Text("SIGTERM?")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Kill") {
                            confirmPID = nil
                            Task { await model.kill(row) }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        Button("Cancel") { confirmPID = nil }
                            .buttonStyle(.borderless)
                    } else {
                        Button {
                            confirmPID = row.pid
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Kill \(row.name)")
                        .accessibilityLabel("Kill \(row.name)")
                    }
                }
            }

            if let error = model.killError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(editingKey ? "Hide API key" : "Set API key") {
                editingKey.toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)

            if editingKey {
                HStack(spacing: 6) {
                    SecureField("oc_sk_…", text: $keyText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        UserDefaults.standard.set(keyText.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  forKey: UsageService.keyOverrideDefaultsKey)
                        editingKey = false
                        Task { await model.refreshUsage() }
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text(model.updatedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Never updated")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func row(title: String, value: String, ratio: Double, showsBar: Bool = true) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(value).font(.caption).monospacedDigit()
            }
            if showsBar { MeterBar(value: ratio) }
        }
    }

    private func limitRow(_ title: String, _ window: LimitWindow) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", window.percent))
                    .font(.caption).monospacedDigit().bold()
                if let resetsAt = window.resetsAt {
                    Text("· \(countdown(resetsAt))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            MeterBar(value: window.percent / 100)
        }
    }

    private func countdown(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "resetting" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "in \(days)d \(hours)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private func compact(_ value: Int) -> String {
        value >= 1_000_000 ? String(format: "%.1fM", Double(value) / 1_000_000)
            : value >= 1_000 ? String(format: "%.1fk", Double(value) / 1_000)
            : "\(value)"
    }
}

private struct MeterBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 5)
    }

    private var color: Color {
        if value > 0.85 { return .red }
        if value > 0.6 { return .yellow }
        return .green
    }
}
