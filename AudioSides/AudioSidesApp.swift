import SwiftUI

@main
struct AudioSidesApp: App {
    /// Launch with `-sample-data` (Debug builds) to show sample devices and open
    /// Device Settings, for screenshots. Nothing is read from or written to Core Audio.
    private static let usesSampleData: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-sample-data")
        #else
        false
        #endif
    }()

    @State private var audio: AudioDeviceManager
    @State private var customizations: DeviceCustomizations
    @State private var meter = usesSampleData ? InputLevelMeter(sampleLevel: 0.6) : InputLevelMeter()

    init() {
        let customizations = Self.usesSampleData ? DeviceCustomizations.sample() : DeviceCustomizations()
        let audio = Self.usesSampleData ? AudioDeviceManager.sample() : AudioDeviceManager()
        audio.customizations = customizations
        audio.applyPreferredInput()
        _audio = State(initialValue: audio)
        _customizations = State(initialValue: customizations)
    }

    var body: some Scene {
        MenuBarExtra {
            SoundPanel()
                .environment(audio)
                .environment(customizations)
                .environment(meter)
        } label: {
            MenuBarIcon(audio: audio)
        }
        .menuBarExtraStyle(.window)

        Window("Device Settings", id: DeviceSettingsView.windowID) {
            DeviceSettingsView()
                .environment(audio)
                .environment(customizations)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 760)
        .defaultLaunchBehavior(Self.usesSampleData ? .presented : .suppressed)
        .restorationBehavior(.disabled)
    }
}

/// Shows the current output device's symbol, the way the system Sound menu does.
private struct MenuBarIcon: View {
    let audio: AudioDeviceManager

    var body: some View {
        let output = audio.outputDevices.first { $0.id == audio.defaultOutputID }
        Image(systemName: output?.systemImage(for: .output) ?? AudioDirection.output.systemImage)
            .accessibilityLabel("AudioSides")
    }
}
