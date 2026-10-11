import Foundation
import Observation

/// User-chosen names and hidden devices.
///
/// Devices are keyed by Core Audio UID so settings survive reconnects and restarts.
/// A name applies to both sides of a device; hiding is per side, so a device can be
/// hidden as a speaker but still offered as a microphone.
@Observable
final class DeviceCustomizations {
    private(set) var names: [String: String]
    private(set) var hiddenOutputUIDs: Set<String>
    private(set) var hiddenInputUIDs: Set<String>
    /// The "Keep my mic" choice, and its name for showing while it's disconnected.
    private(set) var preferredInputUID: String?
    private(set) var preferredInputName: String?

    /// Whether the menu shows a live level for the selected microphone.
    var showsInputLevel: Bool {
        didSet { defaults.set(showsInputLevel, forKey: Key.showsInputLevel) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let names = "deviceNames"
        static let hiddenOutput = "hiddenOutputDeviceUIDs"
        static let hiddenInput = "hiddenInputDeviceUIDs"
        static let preferredInputUID = "preferredInputUID"
        static let preferredInputName = "preferredInputName"
        static let showsInputLevel = "showsInputLevel"
        /// Before hiding was per side; migrated to both sides.
        static let legacyHidden = "hiddenDeviceUIDs"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.dictionary(forKey: Key.names) as? [String: String] ?? [:]
        preferredInputUID = defaults.string(forKey: Key.preferredInputUID)
        preferredInputName = defaults.string(forKey: Key.preferredInputName)
        showsInputLevel = defaults.object(forKey: Key.showsInputLevel) as? Bool ?? true

        let legacy = Set(defaults.stringArray(forKey: Key.legacyHidden) ?? [])
        hiddenOutputUIDs = Set(defaults.stringArray(forKey: Key.hiddenOutput) ?? []).union(legacy)
        hiddenInputUIDs = Set(defaults.stringArray(forKey: Key.hiddenInput) ?? []).union(legacy)
        if !legacy.isEmpty {
            defaults.removeObject(forKey: Key.legacyHidden)
            saveHidden()
        }
    }

    // MARK: Names

    func displayName(for device: AudioDevice) -> String {
        names[device.uid] ?? device.shortName
    }

    func hasCustomName(_ device: AudioDevice) -> Bool {
        names[device.uid] != nil
    }

    /// Sets a custom name. A blank name, or one matching the default, resets to the default.
    func setName(_ name: String, for device: AudioDevice) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDefault = trimmed.isEmpty || trimmed == device.shortName
        names[device.uid] = isDefault ? nil : trimmed
        defaults.set(names, forKey: Key.names)
        if isPreferredInput(device) {
            preferredInputName = displayName(for: device)
            defaults.set(preferredInputName, forKey: Key.preferredInputName)
        }
    }

    // MARK: Keep my mic

    func setPreferredInput(_ device: AudioDevice?) {
        preferredInputUID = device?.uid
        preferredInputName = device.map(displayName)
        defaults.set(preferredInputUID, forKey: Key.preferredInputUID)
        defaults.set(preferredInputName, forKey: Key.preferredInputName)
    }

    func isPreferredInput(_ device: AudioDevice) -> Bool {
        device.uid == preferredInputUID
    }

    // MARK: Visibility

    func isHidden(_ device: AudioDevice, for direction: AudioDirection) -> Bool {
        hiddenUIDs(for: direction).contains(device.uid)
    }

    func setHidden(_ hidden: Bool, for device: AudioDevice, direction: AudioDirection) {
        switch direction {
        case .output:
            if hidden { hiddenOutputUIDs.insert(device.uid) } else { hiddenOutputUIDs.remove(device.uid) }
        case .input:
            if hidden { hiddenInputUIDs.insert(device.uid) } else { hiddenInputUIDs.remove(device.uid) }
        }
        saveHidden()
    }

    private func hiddenUIDs(for direction: AudioDirection) -> Set<String> {
        switch direction {
        case .output: hiddenOutputUIDs
        case .input: hiddenInputUIDs
        }
    }

    private func saveHidden() {
        defaults.set(hiddenOutputUIDs.sorted(), forKey: Key.hiddenOutput)
        defaults.set(hiddenInputUIDs.sorted(), forKey: Key.hiddenInput)
    }
}
