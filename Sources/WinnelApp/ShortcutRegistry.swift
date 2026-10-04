import AppKit
@preconcurrency import Carbon

struct ShortcutSpec: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    static let palette = ShortcutSpec(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey))
    static let next = ShortcutSpec(keyCode: 45, modifiers: UInt32(cmdKey | shiftKey))
    var displayName: String {
        let labels: [(Int, String)] = [(controlKey, "Control"), (optionKey, "Option"), (shiftKey, "Shift"), (cmdKey, "Command")]
        let keys = labels.filter { modifiers & UInt32($0.0) != 0 }.map(\.1)
        let key = keyCode == 49 ? "Space" : keyCode == 45 ? "N" : "Key \(keyCode)"
        return (keys + [key]).joined(separator: "–")
    }
}
@MainActor final class ShortcutRegistry {
    private var registrations: [EventHotKeyRef] = []
    private var activePair: (ShortcutSpec, ShortcutSpec)?
    private var handler: EventHandlerRef?
    var onPalette: () -> Void = {}
    var onNext: () -> Void = {}
    private(set) var error: String?
    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
            let registry = Unmanaged<ShortcutRegistry>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { if identifier.id == 1 { registry.onPalette() }; if identifier.id == 2 { registry.onNext() } }
            return noErr
        }, 1, &event, context, &handler)
    }
    @discardableResult func configure(palette: ShortcutSpec, next: ShortcutSpec) -> Bool {
        guard palette != next, ![palette, next].contains(where: { $0.keyCode == 9 && $0.modifiers == UInt32(cmdKey) }),
              [palette, next].allSatisfy({ $0.modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 }) else {
            error = "Choose two distinct shortcuts with Command, Control or Option. Command-V is reserved for normal paste."; return false
        }
        let previous = activePair
        unregister()
        for (index, shortcut) in [palette, next].enumerated() {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x57696e6e, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else {
                unregister(); activePair = nil
                let restored = previous.map { configure(palette: $0.0, next: $0.1) } ?? false
                error = restored ? "A shortcut is unavailable. The previous working shortcuts were restored." : "Shortcuts are unavailable. Open Winnel from the menu bar and choose different shortcuts in Settings."; return false
            }
            registrations.append(reference)
        }
        activePair = (palette, next); error = nil; return true
    }
    func unregister() { for reference in registrations { UnregisterEventHotKey(reference) }; registrations.removeAll() }
}

import SwiftUI
extension Notification.Name { static let winnelShortcutsChanged = Notification.Name("WinnelShortcutsChanged") }
struct ShortcutSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var paletteModifiers = UInt32(cmdKey | shiftKey)
    @State private var nextModifiers = UInt32(cmdKey | shiftKey)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard shortcuts").font(.headline)
            Picker("Open palette (Space)", selection: $paletteModifiers) { choices }
            Picker("Queue Next (N)", selection: $nextModifiers) { choices }
            Button("Apply shortcuts") {
                model.updateSettings { settings in
                    settings.paletteShortcutKeyCode = 49; settings.paletteShortcutModifiers = paletteModifiers
                    settings.nextShortcutKeyCode = 45; settings.nextShortcutModifiers = nextModifiers
                }
            }
            Text("Normal Command-V always belongs to macOS. Shortcut conflicts appear in the status message.").font(.caption).foregroundStyle(.secondary)
        }.onAppear {
            paletteModifiers = model.state.settings.paletteShortcutModifiers
            nextModifiers = model.state.settings.nextShortcutModifiers
        }
    }
    private var choices: some View {
        Group {
            Text("Command Shift").tag(UInt32(cmdKey | shiftKey))
            Text("Control Option").tag(UInt32(controlKey | optionKey))
            Text("Command Option").tag(UInt32(cmdKey | optionKey))
        }
    }
}
