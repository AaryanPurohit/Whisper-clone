import Foundation
import Combine

enum HotkeyOption: String, CaseIterable, Codable {
    case control = "Control"
    case option  = "Option (Alt)"
    case shift   = "Shift"

    var displayName: String { rawValue }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @Published var hotkey: HotkeyOption {
        didSet {
            UserDefaults.standard.set(hotkey.rawValue, forKey: Keys.hotkey)
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        }
    }

    @Published var apiKey: String {
        didSet {
            KeychainHelper.save(key: Keys.apiKey, value: apiKey)
        }
    }

    private enum Keys {
        static let hotkey = "hotkey"
        static let apiKey = "openai_api_key"
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Keys.hotkey) ?? HotkeyOption.control.rawValue
        // Fall back to .control if a previously saved value (e.g. "Fn") no longer exists
        self.hotkey = HotkeyOption(rawValue: saved) ?? .control
        self.apiKey = KeychainHelper.load(key: Keys.apiKey) ?? ""
    }
}
