import CoreAudio
import Foundation

/// Realistic devices for SwiftUI previews and the README screenshots.
extension AudioDeviceManager {
    static func sample() -> AudioDeviceManager {
        AudioDeviceManager(
            sampleDevices: SampleDevice.all,
            defaultOutputID: SampleDevice.airPods.id,
            defaultInputID: SampleDevice.yeti.id
        )
    }
}

extension DeviceCustomizations {
    /// A renamed display, the Yeti's headphone jack hidden as a speaker, and the Yeti kept as the mic.
    static func sample() -> DeviceCustomizations {
        let suite = "AudioSides.sample"
        UserDefaults().removePersistentDomain(forName: suite)
        let customizations = DeviceCustomizations(defaults: UserDefaults(suiteName: suite)!)
        customizations.setName("LG Display", for: SampleDevice.lgDisplay)
        customizations.setHidden(true, for: SampleDevice.yeti, direction: .output)
        customizations.setPreferredInput(SampleDevice.yeti)
        return customizations
    }
}

enum SampleDevice {
    static let macBookSpeakers = AudioDevice(
        id: 1, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers",
        transportType: kAudioDeviceTransportTypeBuiltIn, supportsOutput: true, supportsInput: false
    )
    static let macBookMic = AudioDevice(
        id: 2, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone",
        transportType: kAudioDeviceTransportTypeBuiltIn, supportsOutput: false, supportsInput: true
    )
    static let airPods = AudioDevice(
        id: 3, uid: "AirPodsPro", name: "AirPods Pro",
        transportType: kAudioDeviceTransportTypeBluetooth, supportsOutput: true, supportsInput: true
    )
    static let calDigit = AudioDevice(
        id: 4, uid: "CalDigitTS3", name: "CalDigit Thunderbolt 3 Audio",
        transportType: kAudioDeviceTransportTypeUSB, supportsOutput: true, supportsInput: false
    )
    static let yeti = AudioDevice(
        id: 5, uid: "YetiStereo", name: "Yeti Stereo Microphone",
        transportType: kAudioDeviceTransportTypeUSB, supportsOutput: true, supportsInput: true
    )
    static let lgDisplay = AudioDevice(
        id: 6, uid: "LGUltraFine", name: "LG UltraFine Display Audio",
        transportType: kAudioDeviceTransportTypeUSB, supportsOutput: true, supportsInput: true
    )
    static let iPhone = AudioDevice(
        id: 7, uid: "ContinuityMic", name: "iPhone Microphone",
        transportType: kAudioDeviceTransportTypeContinuityCaptureWireless, supportsOutput: false, supportsInput: true
    )

    static let all = [macBookSpeakers, macBookMic, airPods, calDigit, yeti, lgDisplay, iPhone]
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
