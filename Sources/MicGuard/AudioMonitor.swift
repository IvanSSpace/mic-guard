import Foundation
import CoreAudio

enum Transport {
    case builtIn
    case usb
    case bluetooth
    case virtual
    case other
}

struct AudioDeviceInfo {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: Transport
}

final class MonitorState: ObservableObject {
    static let shared = MonitorState()
    @Published var currentInputName: String = "—"
    @Published var currentInputIsBluetooth: Bool = false
    @Published var rankedDevices: [AudioDeviceInfo] = []
}

final class AudioMonitor {
    static let shared = AudioMonitor()

    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private let queue = DispatchQueue(label: "mic-guard.audio-monitor")

    func start() {
        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectAddPropertyListenerBlock(systemObjectID, &defaultInputAddress, queue) { [weak self] _, _ in
            self?.enforcePolicyOnQueue()
        }
        AudioObjectAddPropertyListenerBlock(systemObjectID, &devicesAddress, queue) { [weak self] _, _ in
            self?.enforcePolicyOnQueue()
        }

        enforcePolicy()
    }

    /// Безопасно вызывать с любого потока (в т.ч. main — например после ручной
    /// перестановки приоритета в UI): всегда уходит на фоновую очередь первым делом.
    func enforcePolicy() {
        queue.async { [weak self] in
            self?.enforcePolicyOnQueue()
        }
    }

    // MARK: - Policy (выполняется только на `queue`)

    private func enforcePolicyOnQueue() {
        let all = allInputDevices()
        guard let currentID = defaultInputDeviceID() else { return }
        let current = all.first(where: { $0.id == currentID })

        // LockState/PriorityStore мутируются из SwiftUI на main thread — читаем и
        // публикуем состояние для UI одним синхронным хопом на main, чтобы не гонять
        // @Published свойства между потоками.
        let (isLocked, ranked, disabledUIDs) = DispatchQueue.main.sync { () -> (Bool, [AudioDeviceInfo], Set<String>) in
            if let current {
                MonitorState.shared.currentInputName = current.name
                MonitorState.shared.currentInputIsBluetooth = current.transport == .bluetooth
            }
            let locked = LockState.shared.isLocked
            let sorted = PriorityStore.shared.sortedAvailable(from: all)
            MonitorState.shared.rankedDevices = sorted
            return (locked, sorted, DeviceEnableStore.shared.disabledUIDs)
        }

        let allowed = ranked.filter {
            !($0.transport == .bluetooth && isLocked) && !disabledUIDs.contains($0.uid)
        }
        guard let desired = allowed.first, desired.id != currentID else { return }
        setDefaultInput(desired.id)
    }

    // MARK: - CoreAudio helpers

    private func address(_ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObjectID, &addr, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private func setDefaultInput(_ deviceID: AudioDeviceID) {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectSetPropertyData(systemObjectID, &addr, 0, nil, size, &id)
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObjectID, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(systemObjectID, &addr, 0, nil, &size, &ids)
        return ids
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
        guard status == noErr, let cfName = name?.takeRetainedValue() else { return "Unknown" }
        return cfName as String
    }

    /// Персистентный идентификатор устройства (переживает переподключение), в отличие
    /// от AudioDeviceID, который выдаётся заново при каждом коннекте — по нему хранится
    /// порядок приоритета.
    private func deviceUID(_ id: AudioDeviceID) -> String {
        var addr = address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid)
        guard status == noErr, let cfUID = uid?.takeRetainedValue() else { return "id-\(id)" }
        return cfUID as String
    }

    private func transportType(_ id: AudioDeviceID) -> Transport {
        var addr = address(kAudioDevicePropertyTransportType)
        var raw: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &raw) == noErr else { return .other }
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return .virtual
        default:
            return .other
        }
    }

    private func hasInputStreams(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private func allInputDevices() -> [AudioDeviceInfo] {
        allDeviceIDs()
            .filter { hasInputStreams($0) }
            .map { AudioDeviceInfo(id: $0, uid: deviceUID($0), name: deviceName($0), transport: transportType($0)) }
    }
}
