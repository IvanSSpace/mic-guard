import SwiftUI
import AppKit

private struct DeviceRow: View {
    let device: AudioDeviceInfo
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

            Image(systemName: icon).frame(width: 16)
            Text(device.name)
                .lineLimit(1)
                .strikethrough(isBlocked)
                .foregroundStyle(isBlocked ? .secondary : .primary)
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
        .font(.system(size: 12))
    }
}

struct MicGuardPanel: View {
    @ObservedObject var lockState = LockState.shared
    @ObservedObject var monitorState = MonitorState.shared

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
                ForEach(monitorState.rankedDevices, id: \.uid) { device in
                    DeviceRow(device: device, isLocked: lockState.isLocked)
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
        }
        .menuBarExtraStyle(.window)
    }
}
