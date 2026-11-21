import SwiftUI

struct ActivitySection: View {
    @ObservedObject var processes: ProcessMonitor
    @ObservedObject var ports: PortMonitor

    @State private var confirmPID: Int32?
    @State private var confirmPort: String?
    @State private var activity: Activity = .ports

    private enum Activity { case ports, processes }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PanelLabel("Activity")
                Spacer()
                HStack(spacing: 6) {
                    tab("PORTS \(ports.rows.value?.count ?? 0)", active: activity == .ports) {
                        activity = .ports
                    }
                    tab("PROCS \(processes.rows.value?.count ?? 0)", active: activity == .processes) {
                        activity = .processes
                    }
                }
            }

            switch activity {
            case .ports: portList
            case .processes: processList
            }
        }
        .card()
        .onChange(of: activity) { _ in
            if activity == .ports { ports.refresh() } else { processes.refresh() }
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
            if let rows = ports.rows.value, rows.isEmpty {
                Text("No listening port").font(.system(size: 10)).foregroundStyle(Bru.muted)
                    .frame(height: 62, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ports.rows.value ?? []) { row in
                            HStack(spacing: 6) {
                                if confirmPort == row.id {
                                    SlabButton("SIGTERM", fill: Bru.red, text: .white) {
                                        confirmPort = nil
                                        Task { await ports.kill(row) }
                                    }
                                    SlabButton("CANCEL", fill: Bru.paper, text: Bru.ink) {
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
            if let error = ports.rows.error {
                Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
            }
        }
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(processes.rows.value ?? []) { row in
                        HStack(spacing: 6) {
                            if confirmPID == row.pid {
                                SlabButton("SIGTERM", fill: Bru.red, text: .white) {
                                    confirmPID = nil
                                    Task { await processes.kill(row) }
                                }
                                SlabButton("CANCEL", fill: Bru.paper, text: Bru.ink) {
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
            if let error = processes.rows.error {
                Text(error).font(.system(size: 9)).foregroundStyle(Bru.red)
            }
        }
    }
}
