import CoreAudio
import Foundation
import Observation

/// Tracks the system's audio devices and the current default input and output,
/// and lets either be changed independently.
@Observable
final class AudioDeviceManager {
    /// Every device that can be a default input or output.
    private(set) var allDevices: [AudioDevice] = []
    private(set) var outputDevices: [AudioDevice] = []
    private(set) var inputDevices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioObjectID?
    private(set) var defaultInputID: AudioObjectID?
    var errorMessage: String?

    /// Supplies the preferred microphone for the "Keep my mic" rule.
    @ObservationIgnored weak var customizations: DeviceCustomizations?

    @ObservationIgnored private var knownDeviceIDs: Set<AudioObjectID>?
    @ObservationIgnored private var connectionTimes: [AudioObjectID: Date] = [:]
    @ObservationIgnored private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    @ObservationIgnored private let usesSampleData: Bool

    init() {
        usesSampleData = false
        refresh()
        startListening()
    }

    /// Fixed devices for SwiftUI previews and screenshots. Never touches Core Audio;
    /// picking a device just updates the selection.
    init(sampleDevices: [AudioDevice], defaultOutputID: AudioObjectID?, defaultInputID: AudioObjectID?) {
        usesSampleData = true
        allDevices = sampleDevices
        outputDevices = sampleDevices.filter(\.supportsOutput)
        inputDevices = sampleDevices.filter(\.supportsInput)
        self.defaultOutputID = defaultOutputID
        self.defaultInputID = defaultInputID
    }

    isolated deinit {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }

    func devices(for direction: AudioDirection) -> [AudioDevice] {
        switch direction {
        case .output: outputDevices
        case .input: inputDevices
        }
    }

    func defaultDeviceID(for direction: AudioDirection) -> AudioObjectID? {
        switch direction {
        case .output: defaultOutputID
        case .input: defaultInputID
        }
    }

    func setDefault(_ device: AudioDevice, for direction: AudioDirection) {
        guard device.id != defaultDeviceID(for: direction) else { return }

        if usesSampleData {
            switch direction {
            case .output: defaultOutputID = device.id
            case .input: defaultInputID = device.id
            }
            return
        }

        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: direction.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        )

        if status == noErr {
            errorMessage = nil
        } else {
            errorMessage = "Couldn’t switch to \(device.name) (error \(status))."
        }
        refresh()
    }

    // MARK: - Keep my mic

    /// Switches to the preferred microphone now, if it's connected.
    func applyPreferredInput() {
        guard let preferred = preferredInput() else { return }
        setDefault(preferred, for: .input)
    }

    /// Undoes an input switch caused by a device connecting, such as AirPods taking
    /// over the mic, and switches to the preferred mic when it connects. Choices made
    /// by hand, here or in System Settings, are left alone.
    private func keepPreferredInput(newlyConnected: Set<AudioObjectID>) {
        let now = Date()
        connectionTimes = connectionTimes.filter { now.timeIntervalSince($0.value) < Self.takeoverWindow }

        guard let preferred = preferredInput(), let current = defaultInputID else { return }
        if Self.shouldRestore(
            preferred: preferred.id,
            current: current,
            newlyConnected: newlyConnected,
            recentlyConnected: Set(connectionTimes.keys)
        ) {
            setDefault(preferred, for: .input)
        }
    }

    /// How long after a device connects its takeover of the input is still undone.
    private static let takeoverWindow: TimeInterval = 10

    nonisolated static func shouldRestore(
        preferred: AudioObjectID,
        current: AudioObjectID,
        newlyConnected: Set<AudioObjectID>,
        recentlyConnected: Set<AudioObjectID>
    ) -> Bool {
        guard current != preferred else { return false }
        return newlyConnected.contains(preferred) || recentlyConnected.contains(current)
    }

    private func preferredInput() -> AudioDevice? {
        guard let uid = customizations?.preferredInputUID else { return nil }
        return inputDevices.first { $0.uid == uid }
    }

    // MARK: - Reading state

    func refresh() {
        guard !usesSampleData else { return }
        allDevices = Self.allDeviceIDs().compactMap(Self.makeDevice)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        outputDevices = allDevices.filter(\.supportsOutput)
        inputDevices = allDevices.filter(\.supportsInput)
        defaultOutputID = Self.defaultDeviceID(for: .output)
        defaultInputID = Self.defaultDeviceID(for: .input)

        let ids = Set(allDevices.map(\.id))
        let newlyConnected = knownDeviceIDs.map { ids.subtracting($0) } ?? []
        knownDeviceIDs = ids
        for id in newlyConnected { connectionTimes[id] = Date() }
        keepPreferredInput(newlyConnected: newlyConnected)
    }

    private func startListening() {
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ]

        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            // Delivered on the main queue, so it is safe to touch main-actor state.
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block
            )
            if status == noErr {
                listeners.append((address, block))
            }
        }
    }

    // MARK: - Microphone activity

    /// Whether any process, this one included, is using the device.
    nonisolated static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        uint32(kAudioDevicePropertyDeviceIsRunningSomewhere, of: device) == 1
    }

    /// Whether a process other than this one is using the device for input. A process
    /// that doesn't say which devices it uses counts as using it.
    nonisolated static func isInputInUseByOtherApps(_ device: AudioObjectID) -> Bool {
        let ownPID = getpid()
        return objectIDs(kAudioHardwarePropertyProcessObjectList, of: AudioObjectID(kAudioObjectSystemObject)).contains { process in
            guard processID(process) != ownPID,
                  uint32(kAudioProcessPropertyIsRunningInput, of: process) == 1
            else { return false }
            let devices = objectIDs(kAudioProcessPropertyDevices, of: process, scope: kAudioObjectPropertyScopeInput)
            return devices.isEmpty || devices.contains(device)
        }
    }

    private nonisolated static func processID(_ process: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid) == noErr else { return nil }
        return pid
    }

    private nonisolated static func objectIDs(
        _ selector: AudioObjectPropertySelector,
        of object: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    // MARK: - Core Audio helpers

    private nonisolated static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func defaultDeviceID(for direction: AudioDirection) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: direction.defaultDeviceSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private nonisolated static func makeDevice(id: AudioObjectID) -> AudioDevice? {
        guard let name = string(kAudioObjectPropertyName, of: id),
              let uid = string(kAudioDevicePropertyDeviceUID, of: id)
        else { return nil }

        if uint32(kAudioDevicePropertyIsHidden, of: id) == 1 { return nil }

        let supportsOutput = canBeDefault(id, direction: .output)
        let supportsInput = canBeDefault(id, direction: .input)
        guard supportsOutput || supportsInput else { return nil }

        return AudioDevice(
            id: id,
            uid: uid,
            name: name,
            transportType: uint32(kAudioDevicePropertyTransportType, of: id) ?? 0,
            supportsOutput: supportsOutput,
            supportsInput: supportsInput
        )
    }

    /// A device qualifies for a direction when it has streams in that scope and
    /// Core Audio allows it to be the default device for it.
    private nonisolated static func canBeDefault(_ id: AudioObjectID, direction: AudioDirection) -> Bool {
        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: direction.scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streamsAddress, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        return uint32(kAudioDevicePropertyDeviceCanBeDefaultDevice, of: id, scope: direction.scope) == 1
    }

    private nonisolated static func uint32(
        _ selector: AudioObjectPropertySelector,
        of id: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private nonisolated static func string(_ selector: AudioObjectPropertySelector, of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
