import Foundation

/// Известное устройство: имя и тип запоминаются на момент последнего наблюдения,
/// чтобы можно было показать устройство в UI и когда оно физически не подключено
/// (id в CoreAudio у отключённого устройства попросту не существует).
struct KnownDevice: Codable {
    let uid: String
    var name: String
    var transport: Transport
}

/// Порядок приоритета входов, ключуется по persistent device UID (не по AudioDeviceID —
/// тот меняется при каждом переподключении). Все методы дёргать только с main thread.
final class PriorityStore: ObservableObject {
    static let shared = PriorityStore()

    private static let key = "MicGuardKnownDevicesOrder"

    @Published private(set) var known: [KnownDevice]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([KnownDevice].self, from: data) {
            known = decoded
        } else {
            known = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(known) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// Обновляет имя/тип уже известных устройств (могли переименоваться) и дописывает
    /// новые в конец списка — низший приоритет по умолчанию. Возвращает доступные
    /// сейчас устройства, отсортированные по рангу — для policy-движка.
    @discardableResult
    func syncKnownDevices(from devices: [AudioDeviceInfo]) -> [AudioDeviceInfo] {
        var changed = false
        let byUID = Dictionary(uniqueKeysWithValues: devices.map { ($0.uid, $0) })

        for i in known.indices {
            guard let live = byUID[known[i].uid] else { continue }
            if known[i].name != live.name || known[i].transport != live.transport {
                known[i].name = live.name
                known[i].transport = live.transport
                changed = true
            }
        }

        let knownUIDs = Set(known.map(\.uid))
        for device in devices where !knownUIDs.contains(device.uid) {
            known.append(KnownDevice(uid: device.uid, name: device.name, transport: device.transport))
            changed = true
        }

        if changed { persist() }

        return known.compactMap { byUID[$0.uid] }
    }

    /// Полный список для UI: и подключённые сейчас, и когда-то виденные, но сейчас
    /// отсутствующие — с флагом isConnected, чтобы показать "вернётся сам при подключении".
    func displayList(available: [AudioDeviceInfo]) -> [DisplayDevice] {
        let availableByUID = Dictionary(uniqueKeysWithValues: available.map { ($0.uid, $0) })
        return known.map { device in
            let live = availableByUID[device.uid]
            return DisplayDevice(
                uid: device.uid,
                name: live?.name ?? device.name,
                transport: live?.transport ?? device.transport,
                isConnected: live != nil
            )
        }
    }

    func moveUp(_ uid: String) {
        guard let idx = known.firstIndex(where: { $0.uid == uid }), idx > 0 else { return }
        known.swapAt(idx, idx - 1)
        persist()
    }

    func moveDown(_ uid: String) {
        guard let idx = known.firstIndex(where: { $0.uid == uid }), idx < known.count - 1 else { return }
        known.swapAt(idx, idx + 1)
        persist()
    }
}
