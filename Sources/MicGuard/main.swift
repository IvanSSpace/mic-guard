import SwiftUI
import AppKit

private struct DeviceRow: View {
    let device: DisplayDevice
    let isLocked: Bool
    @ObservedObject var enableStore = DeviceEnableStore.shared

    private var isManuallyDisabled: Bool { enableStore.disabledUIDs.contains(device.uid) }
    private var isBluetoothBlocked: Bool { device.transport == .bluetooth && isLocked }
    private var isBlocked: Bool { isBluetoothBlocked || isManuallyDisabled }

    private var icon: String {
        switch device.transport {
        case .builtIn: return "laptopcomputer"
        case .usb: return "cable.connector"
        case .bluetooth: return "wave.3.right"
        case .virtual, .other: return "questionmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { !isManuallyDisabled },
                    set: { enabled in
                        if enabled {
                            DeviceEnableStore.shared.enable(device.uid)
                        } else {
                            DeviceEnableStore.shared.disable(device.uid)
                        }
                        AudioMonitor.shared.enforcePolicy()
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()

                Circle()
                    .fill(device.isConnected ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)

                Image(systemName: icon).frame(width: 16)
                Text(device.name)
                    .lineLimit(1)
                    .strikethrough(isBlocked)
                    .foregroundStyle(isBlocked ? .secondary : (device.isConnected ? .primary : .secondary))
                if isBluetoothBlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    PriorityStore.shared.moveUp(device.uid)
                    AudioMonitor.shared.enforcePolicy()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)

                Button {
                    PriorityStore.shared.moveDown(device.uid)
                    AudioMonitor.shared.enforcePolicy()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
            }
            if !device.isConnected {
                Text(isManuallyDisabled ? "не подключён, выключен вручную" : "не подключён — станет входом сам при подключении")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
        }
        .font(.system(size: 12))
    }
}

private func deviceCountLabel(_ n: Int) -> String {
    let mod100 = n % 100
    let mod10 = n % 10
    if (11...14).contains(mod100) { return "Ещё \(n) устройств" }
    switch mod10 {
    case 1: return "Ещё \(n) устройство"
    case 2, 3, 4: return "Ещё \(n) устройства"
    default: return "Ещё \(n) устройств"
    }
}

struct MicGuardPanel: View {
    @ObservedObject var lockState = LockState.shared
    @ObservedObject var monitorState = MonitorState.shared
    @State private var showOtherDevices = false

    /// Реальные микрофоны — то, что физически выбирают как вход.
    private var physicalDevices: [DisplayDevice] {
        monitorState.displayDevices.filter { $0.transport != .virtual && $0.transport != .other }
    }

    /// Виртуальные/неопознанные устройства (Loopback, Screaming Bee, Zoom и т.п.) —
    /// шум от других приложений, а не то, что реально выбирают руками. Сворачиваем.
    private var otherDevices: [DisplayDevice] {
        monitorState.displayDevices.filter { $0.transport == .virtual || $0.transport == .other }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "mic.fill")
                Text("Mic Guard").font(.headline)
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Текущий вход").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: monitorState.currentInputIsBluetooth ? "wave.3.right.circle.fill" : "waveform.circle.fill")
                    Text(monitorState.currentInputName)
                }
            }

            Divider()

            Toggle(isOn: $lockState.isLocked) {
                Text("Блокировать Bluetooth-микрофон")
            }
            .toggleStyle(.switch)
            .onChange(of: lockState.isLocked) { _, _ in
                AudioMonitor.shared.enforcePolicy()
            }

            Text(lockState.isLocked
                 ? "Bluetooth-наушники никогда не станут входом. Приоритет — по списку ниже."
                 : "Bluetooth разрешён как вход по приоритету, пока не включишь блок обратно.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Приоритет входов").font(.caption).foregroundStyle(.secondary)
                ForEach(physicalDevices, id: \.uid) { device in
                    DeviceRow(device: device, isLocked: lockState.isLocked)
                }

                if !otherDevices.isEmpty {
                    DisclosureGroup(isExpanded: $showOtherDevices) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(otherDevices, id: \.uid) { device in
                                DeviceRow(device: device, isLocked: lockState.isLocked)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text(deviceCountLabel(otherDevices.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Выйти") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

@main
struct MicGuardApp: App {
    @ObservedObject private var lockState = LockState.shared

    init() {
        AudioMonitor.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MicGuardPanel()
        } label: {
            Image(systemName: lockState.isLocked ? "mic.slash.circle.fill" : "mic.circle.fill")
                .font(.system(size: 15, weight: .black))
        }
        .menuBarExtraStyle(.window)
    }
}
