import Foundation
import Combine

final class LockState: ObservableObject {
    static let shared = LockState()

    private static let key = "MicGuardBluetoothLocked"

    @Published var isLocked: Bool {
        didSet { UserDefaults.standard.set(isLocked, forKey: Self.key) }
    }

    var isUnlocked: Bool { !isLocked }

    private init() {
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            UserDefaults.standard.set(true, forKey: Self.key)
        }
        isLocked = UserDefaults.standard.bool(forKey: Self.key)
    }
}
