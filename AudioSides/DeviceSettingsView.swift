import ServiceManagement
import SwiftUI

/// Settings in one scrolling pane: each side's devices (rename and hide), then general
/// options, with Quit always in reach at the bottom. Names apply to both the speaker
/// and microphone side; hiding is per side.
struct DeviceSettingsView: View {
    static let windowID = "device-settings"

    @Environment(AudioDeviceManager.self) private var audio

    var body: some View {
        // No section footers: on macOS 27, a footer on a section with a header makes a
        // grouped Form draw the first headed section's last row as a footer.
        Form {
            ForEach(AudioDirection.allCases) { direction in
                Section(direction.title) {
                    deviceRows(for: direction)
                }
            }
            Section("General") {
                PreferredMicPicker()
                InputLevelToggle()
                OpenAtLoginToggle()
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 16) {
                    Text("Click a name to rename it. Hidden devices still show in the menu while they’re in use.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Quit AudioSides") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        // Sized on the outside: the bottom bar's spacer would otherwise ask for the
        // whole screen. The list scrolls when there's more than fits.
        .frame(width: 460)
        .frame(minHeight: 400, idealHeight: 760, maxHeight: 900)
        .modifier(EndsEditingOnOutsideClick())
    }

    @ViewBuilder
    private func deviceRows(for direction: AudioDirection) -> some View {
        let devices = audio.devices(for: direction)
        if devices.isEmpty {
            Text("No \(direction.title.localizedLowercase)")
                .foregroundStyle(.secondary)
        }
        ForEach(devices) { device in
            DeviceSettingsRow(device: device, direction: direction)
        }
    }
}

/// Ends text editing when a click lands outside the field being edited.
/// AppKit leaves the field focused when the click hits something that can't take
/// focus (empty space, a switch, a label), so the field would never lose focus.
private struct EndsEditingOnOutsideClick: ViewModifier {
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                    guard let window = event.window,
                          let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
                          let field = editor.delegate as? NSView
                    else { return event }

                    let hit = window.contentView?.superview?.hitTest(event.locationInWindow)
                    if hit.map({ !$0.isDescendant(of: field) }) ?? true {
                        window.makeFirstResponder(nil)
                    }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

/// "Keep my mic": the microphone to return to when a newly connected device,
/// like AirPods, takes over the input.
private struct PreferredMicPicker: View {
    @Environment(AudioDeviceManager.self) private var audio
    @Environment(DeviceCustomizations.self) private var customizations

    var body: some View {
        let preferredUID = customizations.preferredInputUID
        let isConnected = audio.inputDevices.contains { $0.uid == preferredUID }

        Picker(selection: Binding(get: { preferredUID }, set: choose)) {
            Text("Off").tag(String?.none)
            Divider()
            ForEach(audio.inputDevices) { device in
                Text(customizations.displayName(for: device)).tag(Optional(device.uid))
            }
            if let preferredUID, !isConnected {
                Text("\(customizations.preferredInputName ?? "Microphone") (not connected)")
                    .tag(Optional(preferredUID))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep my mic")
                Text("When a device that just connected, like AirPods, takes over the input, switch back to this mic. It can take a second for headphones to settle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func choose(_ uid: String?) {
        customizations.setPreferredInput(audio.inputDevices.first { $0.uid == uid })
        audio.applyPreferredInput()
    }
}

private struct InputLevelToggle: View {
    @Environment(DeviceCustomizations.self) private var customizations

    var body: some View {
        @Bindable var customizations = customizations
        Toggle(isOn: $customizations.showsInputLevel) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show mic level")
                Text("While another app is using your mic, like on a call, the menu shows its level. Nothing is recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct OpenAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        Toggle("Open at Login", isOn: Binding(get: { isEnabled }, set: setEnabled))
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

private struct DeviceSettingsRow: View {
    @Environment(DeviceCustomizations.self) private var customizations
    let device: AudioDevice
    let direction: AudioDirection

    var body: some View {
        let isHidden = customizations.isHidden(device, for: direction)

        HStack(spacing: 12) {
            DeviceIcon(systemImage: device.systemImage(for: direction), isSelected: false, diameter: 22)
                .opacity(isHidden ? 0.5 : 1)

            EditableLabel(
                text: customizations.displayName(for: device),
                placeholder: device.shortName,
                onCommit: { customizations.setName($0, for: device) }
            )
            .opacity(isHidden ? 0.5 : 1)

            Spacer(minLength: 8)

            if customizations.hasCustomName(device) {
                Button("Reset") {
                    customizations.setName("", for: device)
                }
                .buttonStyle(.link)
                .help("Reset to “\(device.shortName)”")
                .accessibilityLabel("Reset name to \(device.shortName)")
            }

            Toggle("Show in menu", isOn: Binding(
                get: { !isHidden },
                set: { customizations.setHidden(!$0, for: device, direction: direction) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(isHidden ? "Hidden from the menu" : "Shown in the menu")
        }
    }
}

/// Text that reads as a clickable label and turns into a text field when clicked.
/// Return or clicking away saves, Escape cancels. What a blank value means is up to `onCommit`.
private struct EditableLabel: View {
    let text: String
    let placeholder: String
    let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField("Name", text: $draft, prompt: Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
        } else {
            Button(action: beginEditing) {
                HStack(spacing: 6) {
                    Text(text)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.primary.opacity(isHovered ? 0.08 : 0), in: .rect(cornerRadius: 6))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .pointerStyle(.link)
            .help("Rename")
            .accessibilityLabel("Rename \(text)")
        }
    }

    private func beginEditing() {
        draft = text
        isEditing = true
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        onCommit(draft)
    }

    private func cancel() {
        isEditing = false
    }
}

#Preview {
    DeviceSettingsView()
        .environment(AudioDeviceManager.sample())
        .environment(DeviceCustomizations.sample())
}
