import SwiftUI

/// A Control Center–style panel listing speakers and microphones. Both lists start
/// open; clicking a side's title collapses it to just the current device. Picking a
/// device changes only that side.
struct SoundPanel: View {
    @Environment(AudioDeviceManager.self) private var audio
    @Environment(DeviceCustomizations.self) private var customizations
    @Environment(InputLevelMeter.self) private var meter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var isOpen = false
    /// Whether each side's list is open, remembered between openings.
    @AppStorage("outputExpanded") private var outputExpanded = true
    @AppStorage("inputExpanded") private var inputExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sound")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.top, 4)

            PanelDivider()

            ForEach(AudioDirection.allCases) { direction in
                SideSection(direction: direction, isExpanded: expansion(for: direction))
            }

            if let message = audio.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .onTapGesture { audio.errorMessage = nil }
            }

            PanelDivider()

            PanelRow(action: showSettings) {
                Text("Device Settings…")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 300)
        .background(WindowVisibility { isOpen = $0 })
        .task(id: isOpen) {
            // Follow other apps starting and stopping the mic while the menu is open.
            while isOpen, !Task.isCancelled {
                updateMeter()
                try? await Task.sleep(for: .seconds(1))
            }
            meter.stop()
        }
        .onChange(of: audio.defaultInputID) { meter.restart(); updateMeter() }
        .onChange(of: customizations.showsInputLevel) { updateMeter() }
        .onDisappear { meter.stop() }
    }

    private func expansion(for direction: AudioDirection) -> Binding<Bool> {
        switch direction {
        case .output: $outputExpanded
        case .input: $inputExpanded
        }
    }

    /// The meter shows only while the menu is open and another app is already using
    /// the mic, as in a call. It never opens an idle mic: that would light the orange
    /// indicator and drop AirPods to call quality just for a peek.
    private func updateMeter() {
        guard isOpen, customizations.showsInputLevel, let input = audio.defaultInputID else {
            return meter.stop()
        }
        // While the meter runs, this app counts as using the mic too, so look past it.
        let inUse = meter.isRunning
            ? AudioDeviceManager.isInputInUseByOtherApps(input)
            : AudioDeviceManager.isRunningSomewhere(input)
        if inUse {
            meter.start()
        } else {
            meter.stop()
        }
    }

    private func showSettings() {
        dismiss()
        openWindow(id: DeviceSettingsView.windowID)
        // A menu bar app isn't frontmost, so bring the window forward explicitly.
        NSApplication.shared.activate()
    }
}

/// One side: a title that collapses or expands the side, then its devices. Collapsed,
/// only the current device shows, so what's active is always visible.
private struct SideSection: View {
    @Environment(AudioDeviceManager.self) private var audio
    @Environment(DeviceCustomizations.self) private var customizations
    @Environment(InputLevelMeter.self) private var meter
    @Environment(\.colorScheme) private var colorScheme
    let direction: AudioDirection
    @Binding var isExpanded: Bool

    var body: some View {
        let selectedID = audio.defaultDeviceID(for: direction)
        // A hidden device still shows while it's in use, so the current choice is always listed.
        let devices = audio.devices(for: direction).filter {
            !customizations.isHidden($0, for: direction) || $0.id == selectedID
        }
        let shown = isExpanded ? devices : devices.filter { $0.id == selectedID }

        SectionHeader(title: direction.title, isExpanded: $isExpanded)

        VStack(alignment: .leading, spacing: 0) {
            if shown.isEmpty {
                Text(devices.isEmpty ? "No \(direction.title.localizedLowercase)" : "None selected")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            ForEach(shown) { device in
                let isSelected = device.id == selectedID
                PanelRow(action: { audio.setDefault(device, for: direction) }) {
                    DeviceIcon(systemImage: device.systemImage(for: direction), isSelected: isSelected)
                    Text(customizations.displayName(for: device))
                        .lineLimit(1)
                    if direction == .input, customizations.isPreferredInput(device) {
                        PinMark()
                    }
                    if direction == .input, isSelected, meter.isRunning {
                        LevelBar(level: meter.level)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Use as \(direction.singularTitle.localizedLowercase)")
            }
        }
        .padding(.vertical, 4)
        .background(Color.wash(colorScheme == .dark ? 0.07 : 0.05, in: colorScheme), in: .rect(cornerRadius: 10))
        .padding(.bottom, 4)
    }
}

/// "Speakers" or "Microphones", with an arrow that collapses or expands the list.
private struct SectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(isHovered || !isExpanded ? 1 : 0.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Shows only the current device" : "Shows all \(title.localizedLowercase)")
    }
}

/// Marks the "Keep my mic" microphone.
private struct PinMark: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .help("Keep my mic")
            .accessibilityLabel("Kept as your mic")
    }
}

/// A full-width row with a hover highlight, like the rows in Control Center.
private struct PanelRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                content
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(minHeight: 24)
            .padding(.vertical, 3)
            .contentShape(.rect)
            .background(
                Color.wash(isHovered ? (colorScheme == .dark ? 0.1 : 0.07) : 0, in: colorScheme),
                in: .rect(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A thin live level for the selected microphone.
private struct LevelBar: View {
    let level: Float
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(Color.wash(colorScheme == .dark ? 0.16 : 0.1, in: colorScheme))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(4, proxy.size.width * CGFloat(level)))
                }
            }
            .frame(width: 56, height: 4)
            .animation(.linear(duration: 0.08), value: level)
            .accessibilityElement()
            .accessibilityLabel("Microphone level")
            .accessibilityValue("\(Int(level * 100)) percent")
    }
}

/// Reports whether the menu's window is on screen. The menu bar keeps the panel's
/// views alive between openings, so onAppear alone doesn't say when it's open.
private struct WindowVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? VisibilityView)?.onChange = onChange
    }

    final class VisibilityView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return onChange(false) }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.report() }
            }
            report()
        }

        private func report() {
            onChange(window?.occlusionState.contains(.visible) ?? false)
        }
    }
}

/// The round device badge. The current device is drawn highlighted, as in Control Center.
struct DeviceIcon: View {
    let systemImage: String
    let isSelected: Bool
    var diameter: CGFloat = 26
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: diameter * 0.46, weight: .medium))
            .foregroundStyle(glyphStyle)
            .frame(width: diameter, height: diameter)
            .background(circleStyle, in: .circle)
            .animation(.snappy, value: isSelected)
    }

    private var glyphStyle: AnyShapeStyle {
        guard isSelected else { return AnyShapeStyle(.primary) }
        return colorScheme == .dark ? AnyShapeStyle(.tint) : AnyShapeStyle(.white)
    }

    private var circleStyle: AnyShapeStyle {
        guard isSelected else {
            return AnyShapeStyle(Color.wash(colorScheme == .dark ? 0.18 : 0.08, in: colorScheme))
        }
        return colorScheme == .dark ? AnyShapeStyle(.white) : AnyShapeStyle(.tint)
    }
}

extension Color {
    /// A plain black or white tint. The menu's glass draws `.primary` with vibrancy,
    /// which washes light tints out completely; plain colors keep these fills visible.
    static func wash(_ opacity: Double, in colorScheme: ColorScheme) -> Color {
        (colorScheme == .dark ? Color.white : Color.black).opacity(opacity)
    }
}

private struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

#Preview {
    SoundPanel()
        .environment(AudioDeviceManager.sample())
        .environment(DeviceCustomizations.sample())
        .environment(InputLevelMeter(sampleLevel: 0.6))
}
