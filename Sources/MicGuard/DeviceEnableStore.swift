import Foundation

/// Ручное вкл/выкл конкретного устройства как кандидата на default input —
/// независимо от физического подключения и от общего Bluetooth-лока.
/// «Выключил» = устройство остаётся подключено, но не выбирается автоматом,
/// пока не включишь обратно. Мутировать только с main thread.
final class DeviceEnableStore: ObservableObject {
    static let shared = DeviceEnableStore()

    private static let key = "MicGuardDisabledDeviceUIDs"

    @Published private(set) var disabledUIDs: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
        disabledUIDs = Set(saved)
    }

    private func persist() {
        UserDefaults.standard.set(Array(disabledUIDs), forKey: Self.key)
    }

    func disable(_ uid: String) {
        disabledUIDs.insert(uid)
        persist()
    }

    func enable(_ uid: String) {
        disabledUIDs.remove(uid)
        persist()
    }
}
