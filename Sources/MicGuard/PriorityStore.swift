import Foundation

/// Стабильный (не рандомизированный между запусками, в отличие от встроенного
/// String.hashValue) выбор индекса в палитре акцентных цветов по UID устройства.
enum DeviceAccent {
    static let paletteSize = 8

    static func preferredIndex(for uid: String) -> Int {
        var hash: UInt64 = 5381
        for byte in uid.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return Int(hash % UInt64(paletteSize))
    }
}

/// Известное устройство: имя и тип запоминаются на момент последнего наблюдения,
/// чтобы можно было показать устройство в UI и когда оно физически не подключено
/// (id в CoreAudio у отключённого устройства попросту не существует).
struct KnownDevice: Codable {
    let uid: String
    var name: String
    var transport: Transport
    /// nil у записей из старого формата (до появления этого поля) и у новых
    /// устройств до первого назначения — syncKnownDevices досчитывает и то, и то.
    var colorIndex: Int?
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
            known.append(KnownDevice(uid: device.uid, name: device.name, transport: device.transport, colorIndex: nil))
            changed = true
        }

        // Назначаем цвет всем, у кого его ещё нет (новые устройства + записи из
        // старого формата без этого поля): предпочтение по хэшу UID, но если слот
        // занят другим устройством — пробуем следующий по кругу, чтобы одновременно
        // видимые микрофоны не совпадали по цвету.
        var usedIndices = Set(known.compactMap(\.colorIndex))
        for i in known.indices where known[i].colorIndex == nil {
            var candidate = DeviceAccent.preferredIndex(for: known[i].uid)
            var attempts = 0
            while usedIndices.contains(candidate) && attempts < DeviceAccent.paletteSize {
                candidate = (candidate + 1) % DeviceAccent.paletteSize
                attempts += 1
            }
            known[i].colorIndex = candidate
            usedIndices.insert(candidate)
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
                isConnected: live != nil,
                colorIndex: device.colorIndex ?? DeviceAccent.preferredIndex(for: device.uid)
            )
        }
    }

    /// Физические микрофоны (builtIn/usb/bluetooth) и виртуальные/неопознанные
    /// (Loopback, Screaming Bee и т.п.) в UI показаны раздельно — реордер должен
    /// переставлять устройство относительно соседей ИЗ ТОЙ ЖЕ группы, иначе клик
    /// «вверх» на видимом физическом микрофоне может на деле поменять его местами
    /// с невидимым виртуальным соседом в общем списке, и ничего не изменится в UI.
    private func isVirtualLike(_ transport: Transport) -> Bool {
        transport == .virtual || transport == .other
    }

    func moveUp(_ uid: String) {
        guard let idx = known.firstIndex(where: { $0.uid == uid }) else { return }
        let group = isVirtualLike(known[idx].transport)
        guard let swapIdx = known[..<idx].lastIndex(where: { isVirtualLike($0.transport) == group }) else { return }
        known.swapAt(idx, swapIdx)
        persist()
    }

    func moveDown(_ uid: String) {
        guard let idx = known.firstIndex(where: { $0.uid == uid }) else { return }
        let group = isVirtualLike(known[idx].transport)
        guard idx + 1 < known.count,
              let swapIdx = known[(idx + 1)...].firstIndex(where: { isVirtualLike($0.transport) == group }) else { return }
        known.swapAt(idx, swapIdx)
        persist()
    }
}
