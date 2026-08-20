import SwiftUI
import AppKit

/// Блёклый акцентный цвет для иконки устройства. Индекс в палитре назначается
/// и хранится в PriorityStore (с избеганием коллизий между одновременно
/// видимыми устройствами) — здесь только сама палитра, порядок должен
/// совпадать с DeviceAccent.paletteSize.
private let deviceAccentPalette: [Color] = [
    Color(red: 0.45, green: 0.58, blue: 0.78), // приглушённый синий
    Color(red: 0.48, green: 0.68, blue: 0.55), // приглушённый зелёный
    Color(red: 0.78, green: 0.48, blue: 0.48), // приглушённый красный
    Color(red: 0.62, green: 0.52, blue: 0.75), // приглушённый фиолетовый
    Color(red: 0.82, green: 0.62, blue: 0.42), // приглушённый оранжевый
    Color(red: 0.42, green: 0.68, blue: 0.68), // приглушённый бирюзовый
    Color(red: 0.78, green: 0.55, blue: 0.65), // приглушённый розовый
    Color(red: 0.72, green: 0.68, blue: 0.42), // приглушённый оливковый
]

private func deviceAccentColor(for device: DisplayDevice) -> Color {
    deviceAccentPalette[device.colorIndex % deviceAccentPalette.count]
}

private struct DeviceRow: View {
    let device: DisplayDevice
    let isLocked: Bool
    /// Только у самого верхнего устройства в приоритете имеет смысл говорить
    /// "подключится — станет входом": для остальных выше по рангу уже что-то
    /// работает, реконнект нижних ничего не поменяет.
    let isTopPriority: Bool
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

                Image(systemName: icon)
                    .foregroundStyle(isBlocked ? .secondary : deviceAccentColor(for: device))
                    .frame(width: 16)
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
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    PriorityStore.shared.moveDown(device.uid)
                    AudioMonitor.shared.enforcePolicy()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !device.isConnected && isTopPriority {
                Text(isManuallyDisabled ? "disconnected, disabled" : "disconnected — auto-activates on connect")
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
            .tint(.blue)
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
                    DeviceRow(device: device, isLocked: lockState.isLocked, isTopPriority: device.uid == physicalDevices.first?.uid)
                }

                if !otherDevices.isEmpty {
                    Button {
                        showOtherDevices.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showOtherDevices ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Text(deviceCountLabel(otherDevices.count))
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showOtherDevices {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(otherDevices, id: \.uid) { device in
                                DeviceRow(device: device, isLocked: lockState.isLocked, isTopPriority: false)
                            }
                        }
                        .padding(.top, 4)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AudioMonitor.shared.start()
        statusBarController = StatusBarController()
    }
}

@main
struct MicGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
