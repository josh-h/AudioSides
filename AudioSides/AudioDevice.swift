import CoreAudio
import Foundation

/// Which side of the audio path a device is being used for.
nonisolated enum AudioDirection: CaseIterable, Identifiable {
    case output
    case input

    var id: Self { self }

    var title: String {
        switch self {
        case .output: "Speakers"
        case .input: "Microphones"
        }
    }

    var singularTitle: String {
        switch self {
        case .output: "Speaker"
        case .input: "Microphone"
        }
    }

    var systemImage: String {
        switch self {
        case .output: "speaker.wave.2.fill"
        case .input: "mic.fill"
        }
    }

    var scope: AudioObjectPropertyScope {
        switch self {
        case .output: kAudioObjectPropertyScopeOutput
        case .input: kAudioObjectPropertyScopeInput
        }
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        switch self {
        case .output: kAudioHardwarePropertyDefaultOutputDevice
        case .input: kAudioHardwarePropertyDefaultInputDevice
        }
    }
}

/// A snapshot of a Core Audio device.
nonisolated struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transportType: UInt32
    let supportsOutput: Bool
    let supportsInput: Bool

    /// The Core Audio name without a trailing "Speakers" or "Microphone",
    /// which the section headers already say.
    var shortName: String {
        for suffix in ["Speakers", "Speaker", "Microphone", "Mic"] {
            guard let range = name.range(of: " " + suffix, options: [.anchored, .backwards, .caseInsensitive]) else {
                continue
            }
            let trimmed = name[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return name
    }

    /// An SF Symbol that best describes the device for a given direction.
    func systemImage(for direction: AudioDirection) -> String {
        let lowercased = name.localizedLowercase

        if lowercased.contains("airpods max") { return "airpods.max" }
        if lowercased.contains("airpods pro") { return "airpods.pro" }
        if lowercased.contains("airpods") { return "airpods" }

        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless:
            return "iphone"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeVirtual:
            return "waveform"
        default:
            return direction.systemImage
        }
    }
}
