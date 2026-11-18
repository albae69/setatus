import AppKit
import SwiftUI

// V3 neo brutalism: hard edges, ink strokes, flat offset shadows.
private enum Bru {
    static let ink = dynamic(light: 0x111111, dark: 0xF4EFE4)
    static let paper = dynamic(light: 0xFFFDF7, dark: 0x181818)
    static let cream = dynamic(light: 0xF4EFE4, dark: 0x0D0D0D)
    static let muted = dynamic(light: 0x6B6459, dark: 0xA39B8C)
    static let onInk = dynamic(light: 0xFFFDF7, dark: 0x111111)
    static let yellow = Color(hex: 0xFFD93D)
    static let blue = Color(hex: 0x4D7CFE)
    static let green = Color(hex: 0x4ADE80)
    static let red = Color(hex: 0xFF5C5C)
    static let cardInk = Color(hex: 0x111111)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: darkMode ? dark : light)
        })
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

private struct CardStyle: ViewModifier {
    var fill: Color = Bru.paper
    var shadow: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    if shadow > 0 {
                        Rectangle().fill(Bru.ink).offset(x: shadow, y: shadow)
                    }
                    Rectangle().fill(fill)
                }
            )
            .overlay(Rectangle().stroke(Bru.ink, lineWidth: 3))
    }
}

private extension View {
    func card(_ fill: Color = Bru.paper, shadow: CGFloat = 6) -> some View {
        modifier(CardStyle(fill: fill, shadow: shadow))
    }

    func slab(_ fill: Color, line: CGFloat = 2, shadow: CGFloat = 0) -> some View {
        background(
            ZStack {
                if shadow > 0 {
                    Rectangle().fill(Bru.ink).offset(x: shadow, y: shadow)
                }
                Rectangle().fill(fill)
            }
        )
        .overlay(Rectangle().stroke(Bru.ink, lineWidth: line))
    }
}

private struct BlockMeter: View {
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

private struct BlockSlider: View {
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

struct PanelView: View {
    @EnvironmentObject private var model: Model
    @State private var confirmPID: Int32?
    @State private var confirmPort: String?
    @State private var activity: Activity = .ports

    private enum Activity { case ports, processes }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            limits
            system
            fan
            charge
            network
            activitySection
        }
        .padding(12)
        .frame(width: 356)
        .background(Rectangle().fill(Bru.cream))
        .onAppear {
            model.refreshPorts()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Bru.yellow)
                .overlay(Rectangle().stroke(Bru.ink, lineWidth: 2))
                .frame(width: 10, height: 10)
            Text("SETATUS")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Bru.ink)
            Spacer()
            Text(model.updatedAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.muted)
            Button {
                Task { await model.refreshUsage() }
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

    // MARK: - OpenCode limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if let usage = model.usage {
                    HStack(alignment: .top) {
                        label("OpenCode · 5 hours", Bru.cardInk)
                        Spacer()
                        Text(usage.rolling.resetsAt.map { "resets \(countdown($0))" } ?? "—")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.cardInk)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.0f", usage.rolling.percent))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.cardInk)
                        Text("%").font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.cardInk)
                        Spacer()
                        if let today = model.today {
                            Text(compact(today.promptTokens + today.completionTokens) + " tok · $" + String(format: "%.2f", today.cost))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Bru.cardInk)
                        }
                    }
                    BlockMeter(value: usage.rolling.percent / 100, color: Bru.cardInk)
                } else if let error = model.usageError {
                    label("OpenCode · 5 hours", Bru.cardInk)
                    Text(error).font(.system(size: 10)).foregroundStyle(Bru.cardInk)
                } else {
                    label("OpenCode · 5 hours", Bru.cardInk)
                    Text("Loading…").font(.system(size: 10)).foregroundStyle(Bru.cardInk)
                }
                if let error = model.usageError, model.usage != nil {
                    Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
                }
            }
            .card(Bru.yellow)

            HStack(spacing: 10) {
                windowCard("Week", model.usage?.weekly)
                windowCard("Month", model.usage?.monthly)
            }
        }
    }

    private func windowCard(_ title: String, _ window: LimitWindow?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                label(title)
                Spacer()
                Text(String(format: "%.0f%%", window?.percent ?? 0))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Bru.ink)
            }
            BlockMeter(value: (window?.percent ?? 0) / 100, segments: 6,
                       color: (window?.percent ?? 0) > 60 ? Bru.red : Bru.ink)
            Text(window?.resetsAt.map { "resets \(countdown($0))" } ?? "—")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(shadow: 4)
    }

    // MARK: - System

    private var system: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("System")
                Spacer()
                Text(temperature("CPU").map { "SMC · \($0)" } ?? "—")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Bru.muted)
            }
            HStack(spacing: 8) {
                tile("CPU",
                     value: String(format: "%.0f%%", model.cpu),
                     detail: temperature("CPU"),
                     ratio: model.cpu / 100,
                     fill: Bru.paper,
                     text: Bru.ink)
                tile("GPU",
                     value: model.gpuUsage.map { String(format: "%.0f%%", $0) } ?? "—",
                     detail: temperature("GPU"),
                     ratio: (model.gpuUsage ?? 0) / 100,
                     fill: Bru.blue,
                     text: .white)
                tile("RAM",
                     value: String(format: "%.0f%%", model.ramPercent),
                     detail: "\(Fmt.memory(model.ramUsed)) / \(Fmt.memory(model.ramTotal))",
                     ratio: model.ramPercent / 100,
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
            label(title, text)
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
            label(title)
            Spacer()
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.ink)
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
        VStack(alignment: .leading, spacing: 9) {
            if let fan = model.fans.first {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        label("Fan")
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%.0f", fan.actual))
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundStyle(Bru.ink)
                                .monospacedDigit()
                            Text("RPM").font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Bru.ink)
                        }
                    }
                    Spacer()
                    Text(model.fanRunning ? "MANUAL" : "AUTO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Bru.cardInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .slab(model.fanRunning ? Bru.yellow : Bru.green)
                }
                BlockSlider(value: Binding(get: { model.fanTarget },
                                           set: { model.fanTarget = $0 }),
                            range: fan.minimum...max(fan.minimum + 1, fan.maximum),
                            step: 50,
                            fill: model.fanRunning ? Bru.yellow : Bru.green) { editing in
                    model.fanEditing = editing
                    if !editing { Task { await model.applyFan(Int(model.fanTarget)) } }
                }
                HStack {
                    fanFoot("MIN", fan.minimum)
                    Spacer()
                    fanFoot("TARGET", fan.target)
                    Spacer()
                    fanFoot("MAX", fan.maximum)
                }
                if let message = model.fanMessage {
                    Text(message).font(.system(size: 9)).foregroundStyle(Bru.muted)
                }
                if model.fanRunning {
                    slabButton("AUTO", fill: Bru.green, text: Bru.cardInk) {
                        Task { await model.applyFan(0) }
                    }
                }
            } else {
                label("Fan")
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

    // MARK: - Charge limit

    private var charge: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    label("Charge limit")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.chargeLimit >= 100 ? "OFF" : "\(model.chargeLimit)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.ink)
                            .monospacedDigit()
                        Text("%").font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Bru.ink)
                    }
                }
                Spacer()
                Text(model.chargeState?.inhibited == true ? "PAUSED" : "SMC LIMIT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Bru.cardInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .slab(model.chargeState?.inhibited == true ? Bru.yellow : Bru.green)
            }
            BlockSlider(value: Binding(get: { Double(model.chargeLimit) },
                                       set: { model.chargeLimit = Int($0) }),
                        range: 50...100,
                        step: 5,
                        fill: model.chargeState?.inhibited == true ? Bru.yellow : Bru.green) { editing in
                if !editing { Task { await model.applyChargeLimit(model.chargeLimit) } }
            }
            .disabled(model.chargeState?.supported == false)
            .opacity(model.chargeState?.supported == false ? 0.5 : 1)
            if let message = chargeMessage {
                Text(message).font(.system(size: 9)).foregroundStyle(Bru.muted)
            }
        }
        .card()
    }

    private var chargeMessage: String? {
        if let error = model.chargeMessage { return error }
        guard let state = model.chargeState else { return nil }
        if !state.supported { return "Charge limit not exposed by this Mac's SMC" }
        guard state.limit > 0, state.limit < 100 else { return nil }
        let percent = Int(state.percent ?? 0)
        return state.inhibited ? "charging paused at \(percent)%" : "holding \(state.limit)%"
    }

    // MARK: - Network

    private var network: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("Internet")
                Spacer()
                slabButton(model.speedTesting ? "TESTING…" : "SPEED TEST", fill: Bru.ink, text: Bru.onInk) {
                    Task { await model.runSpeedTest() }
                }
                .disabled(model.speedTesting)
            }
            HStack(spacing: 12) {
                flow("↓", title: "Download", value: "\(Fmt.rate(model.netDown))/s")
                flow("↑", title: "Upload", value: "\(Fmt.rate(model.netUp))/s")
            }
            HStack {
                Text("\(bytes(model.netTotalIn)) IN · \(bytes(model.netTotalOut)) OUT")
                Spacer()
                Text(model.localIP ?? "—")
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(Bru.muted)

            HStack(spacing: 6) {
                Spacer(minLength: 4)
                if let speed = model.speedTest {
                    Text("↓ \(String(format: "%.1f", speed.down)) · ↑ \(String(format: "%.1f", speed.up)) Mbps")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Bru.ink)
                } else if let error = model.speedTestError {
                    Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
                }
            }
        }
        .card()
    }

    private func flow(_ arrow: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            label("\(arrow) \(title)")
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Bru.ink)
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
                HStack(spacing: 6) {
                    tab("PORTS \(model.ports.count)", active: activity == .ports) { activity = .ports }
                    tab("PROCS \(model.processes.count)", active: activity == .processes) { activity = .processes }
                }
            }

            switch activity {
            case .ports: portList
            case .processes: processList
            }
        }
        .card()
        .onChange(of: activity) { _ in
            if activity == .ports { model.refreshPorts() } else { model.refreshProcesses() }
        }
    }

    private func tab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(active ? Bru.cardInk : Bru.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .slab(active ? Bru.yellow : .clear)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func killButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("✕")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Bru.red)
                .frame(width: 20, height: 20)
                .overlay(Rectangle().stroke(Bru.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var portList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.ports.isEmpty {
                Text("No listening port").font(.system(size: 10)).foregroundStyle(Bru.muted)
                    .frame(height: 62, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.ports) { row in
                            HStack(spacing: 6) {
                                if confirmPort == row.id {
                                    slabButton("SIGTERM", fill: Bru.red, text: .white) {
                                        confirmPort = nil
                                        Task { await model.killPort(row) }
                                    }
                                    slabButton("CANCEL", fill: Bru.paper, text: Bru.ink) {
                                        confirmPort = nil
                                    }
                                } else {
                                    killButton(
                                        help: "Kill \(row.process) on port \(row.port)"
                                    ) { confirmPort = row.id }
                                }
                                Text(row.process).font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Bru.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(":" + String(row.port) + " · " + String(row.pid))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Bru.muted)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 28)
                        }
                    }
                }
                .frame(height: 56)
            }
            if let error = model.portError {
                Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
            }
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.processes) { row in
                        HStack(spacing: 6) {
                            if confirmPID == row.pid {
                                slabButton("SIGTERM", fill: Bru.red, text: .white) {
                                    confirmPID = nil
                                    Task { await model.kill(row) }
                                }
                                slabButton("CANCEL", fill: Bru.paper, text: Bru.ink) {
                                    confirmPID = nil
                                }
                            } else {
                                killButton(help: "Kill \(row.name)") { confirmPID = row.pid }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Bru.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(String(row.pid) + " · " + String(format: "%.1f%%", row.cpu) + " · " + String(format: "%.0f MB", row.memoryMB))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Bru.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 32)
                    }
                }
            }
            .frame(height: 72)
            if let error = model.killError {
                Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
            }
        }
    }

    // MARK: - Helpers

    private func slabButton(_ title: String, fill: Color, text: Color,
                            shadow: CGFloat = 2, action: @escaping () -> Void) -> some View {
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

    private func label(_ text: String, _ color: Color = Bru.muted) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(color)
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
