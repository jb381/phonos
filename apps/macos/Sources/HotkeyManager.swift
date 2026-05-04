import Cocoa
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let record = Self("record", default: .init(.space, modifiers: [.control]))
}

extension KeyboardShortcuts.Shortcut {
    static let phonosDefaultRecord = Self(.space, modifiers: [.control])
}

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}

@MainActor
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    private let migrationKey = "recordShortcutDisabledMigrationDone"

    init() {}

    func start() -> Bool {
        migrateDisabledShortcutIfNeeded()

        KeyboardShortcuts.removeHandler(for: .record)
        KeyboardShortcuts.onKeyDown(for: .record) { [weak self] in
            Task { @MainActor [weak self] in
                self?.delegate?.hotkeyDidPress()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .record) { [weak self] in
            Task { @MainActor [weak self] in
                self?.delegate?.hotkeyDidRelease()
            }
        }
        return true
    }

    func stop() {
        KeyboardShortcuts.removeHandler(for: .record)
    }

    private func migrateDisabledShortcutIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        if KeyboardShortcuts.getShortcut(for: .record) == nil,
           UserDefaults.standard.object(forKey: "KeyboardShortcuts_record") != nil {
            KeyboardShortcuts.setShortcut(.phonosDefaultRecord, for: .record)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
