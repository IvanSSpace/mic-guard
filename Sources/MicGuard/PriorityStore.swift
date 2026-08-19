import Foundation

/// Порядок приоритета входов, ключуется по persistent device UID (не по AudioDeviceID —
/// тот меняется при каждом переподключении). Все методы дёргать только с main thread.
final class PriorityStore: ObservableObject {
    static let shared = PriorityStore()

    private static let key = "MicGuardPriorityOrder"

    @Published private(set) var order: [String]

    private init() {
        order = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    private func persist() {
        UserDefaults.standard.set(order, forKey: Self.key)
    }

    /// Новые (ранее не виденные) устройства уходят в конец списка — низший приоритет
    /// по умолчанию. Возвращает доступные сейчас устройства, отсортированные по рангу.
    func sortedAvailable(from devices: [AudioDeviceInfo]) -> [AudioDeviceInfo] {
        var appended = false
        for device in devices where !order.contains(device.uid) {
            order.append(device.uid)
            appended = true
        }
        if appended { persist() }

        let byUID = Dictionary(uniqueKeysWithValues: devices.map { ($0.uid, $0) })
        return order.compactMap { byUID[$0] }
    }

    func moveUp(_ uid: String) {
        guard let idx = order.firstIndex(of: uid), idx > 0 else { return }
        order.swapAt(idx, idx - 1)
        persist()
    }

    func moveDown(_ uid: String) {
        guard let idx = order.firstIndex(of: uid), idx < order.count - 1 else { return }
        order.swapAt(idx, idx + 1)
        persist()
    }
}
