import AppKit
import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: Model
    @State private var keyText = ""
    @State private var editingKey = false
    @State private var confirmPID: Int32?
    @State private var confirmPort: String?
    @State private var activity: Activity = .ports

    private enum Activity { case ports, processes }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            limits
            system
            fan
            network
            activitySection
            keySection
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            model.refreshPorts()
            Task { keyText = await Task.detached { UsageService.apiKey() }.value ?? "" }
        }
    }

    private var header: some View {
        HStack {
            wordmark
            Spacer()
            Text(model.updatedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Never updated")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
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

    private var wordmark: some View {
        Group {
            if let url = Bundle.main.url(forResource: "wordmark", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 15)
                    .accessibilityLabel("Setatus")
            } else {
                Text("Setatus").font(.headline)
            }
        }
    }

    // MARK: - OpenCode limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let usage = model.usage {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        label("OpenCode · 5 hours")
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%.0f%%", usage.rolling.percent))
                                .font(.system(size: 30, weight: .medium))
                                .monospacedDigit()
                            Text("of 5h window").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(usage.rolling.resetsAt.map { "resets \(countdown($0))" } ?? "—")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                MeterBar(value: usage.rolling.percent / 100)
                HStack(alignment: .top, spacing: 16) {
                    windowColumn("Week", usage.weekly)
                    windowColumn("Month", usage.monthly)
                }
                if let today = model.today {
                    Text("Today  \(today.requests) req · \(compact(today.promptTokens + today.completionTokens)) tok · $\(String(format: "%.2f", today.cost))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else if let error = model.usageError {
                VStack(alignment: .leading, spacing: 4) {
                    label("OpenCode · 5 hours")
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    label("OpenCode · 5 hours")
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.usageError, model.usage != nil {
                Text(error).font(.caption2).foregroundStyle(.orange)
            }
        }
        .card()
    }

    private func windowColumn(_ title: String, _ window: LimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", window.percent))
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
            MeterBar(value: window.percent / 100, height: 3)
            Text(window.resetsAt.map { "resets \(countdown($0))" } ?? "—")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - System

    private var system: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                tile("CPU",
                     value: String(format: "%.0f%%", model.cpu),
                     detail: temperature("CPU"),
                     ratio: model.cpu / 100)
                tile("GPU",
                     value: model.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "—",
                     detail: temperature("GPU"),
                     ratio: (model.gpuUsage ?? 0) / 100)
                tile("RAM",
                     value: String(format: "%.0f%%", model.ramPercent),
                     detail: "\(Fmt.memory(model.ramUsed)) / \(Fmt.memory(model.ramTotal))",
                     ratio: model.ramPercent / 100)
            }
            infoRow("Power", powerText)
            infoRow("Uptime", uptimeText)
        }
    }

    private func tile(_ title: String, value: String, detail: String?, ratio: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                Spacer(minLength: 4)
                if let detail {
                    Text(detail).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            MeterBar(value: ratio, height: 3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
    }

    private func temperature(_ name: String) -> String? {
        model.temps.first { $0.label == name }.map { String(format: "%.0f °C", $0.celsius) }
    }

    private var uptimeText: String {
        var parts = [Fmt.duration(model.uptime)]
        let known: Set<String> = ["CPU", "GPU"]
        parts += model.temps.filter { !known.contains($0.label) }.prefix(2)
            .map { String(format: "%@ %.0f°C", $0.label, $0.celsius) }
        return parts.joined(separator: " · ")
    }

    private var powerText: String {
        guard let power = model.power else { return "—" }
        var parts: [String] = []
        if let input = power.inputWatts { parts.append(Fmt.watts(input)) }
        if let adapter = power.adapterWatts { parts.append(String(format: "%.0f W adapter", adapter)) }
        if let percent = power.batteryPercent {
            parts.append(String(format: "%.0f%%", percent) + (power.charging ? " charging" : ""))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: - Fan

    private var fan: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fan = model.fans.first {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        label("Fan")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.0f", fan.actual))
                                .font(.system(size: 20, weight: .medium))
                                .monospacedDigit()
                            Text("rpm").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.fanRunning ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(model.fanRunning ? "Manual" : "Auto")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                }
                Slider(value: Binding(get: { model.fanTarget },
                                      set: { model.fanTarget = $0 }),
                       in: fan.minimum...max(fan.minimum + 1, fan.maximum),
                       step: 50) { editing in
                    model.fanEditing = editing
                    if !editing { Task { await model.applyFan(Int(model.fanTarget)) } }
                }
                .tint(model.fanRunning ? .orange : .accentColor)
                HStack {
                    Text("min \(Int(fan.minimum.rounded()))")
                    Spacer()
                    Text("target \(Int(fan.target.rounded()))")
                    Spacer()
                    Text("max \(Int(fan.maximum.rounded()))")
                }
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                if let message = model.fanMessage {
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                }
                if model.fanRunning {
                    Button("Auto") { Task { await model.applyFan(0) } }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    label("Fan")
                    Text("No fan detected").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    // MARK: - Network

    private var network: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                flow("↓", title: "Download", value: "\(Fmt.rate(model.netDown))/s")
                flow("↑", title: "Upload", value: "\(Fmt.rate(model.netUp))/s")
            }
            HStack {
                Text("\(bytes(model.netTotalIn)) in · \(bytes(model.netTotalOut)) out")
                Spacer()
                Text(model.localIP ?? "—")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .card()
    }

    private func flow(_ arrow: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label("\(arrow) \(title)")
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ports + processes

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("Activity")
                Spacer()
                Picker("Activity", selection: $activity) {
                    Text("Ports \(model.ports.count)").tag(Activity.ports)
                    Text("Processes \(model.processes.count)").tag(Activity.processes)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 190)
                .onChange(of: activity) { _ in
                    if activity == .ports { model.refreshPorts() } else { model.refreshProcesses() }
                }
            }

            switch activity {
            case .ports: portList
            case .processes: processList
            }
        }
        .card()
    }

    private var portList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.ports.isEmpty {
                Text("No dev port in use").font(.caption2).foregroundStyle(.secondary)
                    .frame(height: 90, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.ports) { row in
                            HStack(spacing: 8) {
                                Text(row.process).font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(":\(row.port) · \(row.pid)").font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Spacer(minLength: 4)
                                if confirmPort == row.id {
                                    Text("SIGTERM?").font(.system(size: 9)).foregroundStyle(.secondary)
                                    Button("Kill") {
                                        confirmPort = nil
                                        Task { await model.killPort(row) }
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                    Button("Cancel") { confirmPort = nil }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 10))
                                } else {
                                    Button {
                                        confirmPort = row.id
                                    } label: {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.quaternary)
                                    .help("Kill \(row.process) on port \(row.port)")
                                    .accessibilityLabel("Kill \(row.process) on port \(row.port)")
                                }
                            }
                            .frame(height: 30)
                        }
                    }
                }
                .frame(height: 90)
            }
            if let error = model.portError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.processes) { row in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(row.pid) · \(String(format: "%.1f%%", row.cpu)) · \(String(format: "%.0f MB", row.memoryMB))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 4)
                            if confirmPID == row.pid {
                                Text("SIGTERM?").font(.system(size: 9)).foregroundStyle(.secondary)
                                Button("Kill") {
                                    confirmPID = nil
                                    Task { await model.kill(row) }
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                Button("Cancel") { confirmPID = nil }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 10))
                            } else {
                                Button {
                                    confirmPID = row.pid
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 9))
                                .foregroundStyle(.quaternary)
                                .help("Kill \(row.name)")
                                .accessibilityLabel("Kill \(row.name)")
                            }
                        }
                        .frame(height: 30)
                    }
                }
            }
            .frame(height: 120)
            if let error = model.killError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    // MARK: - API key

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(editingKey ? "Hide API key" : "Set API key") {
                    editingKey.toggle()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                Spacer()
            }
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

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private func countdown(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if seconds <= 0 { return "now" }
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

private struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }
}

private extension View {
    func card() -> some View { modifier(Card()) }
}

private struct MeterBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(2, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }

    private var color: Color {
        if value > 0.85 { return .red }
        if value > 0.6 { return .orange }
        return .green
    }
}
