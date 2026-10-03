import AppKit
import SwiftUI
import Combine
import WinnelPlatform
import WinnelCore

final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: AppModel
    private var statusItem: NSStatusItem?
    private var panel: PalettePanel?
    private var library: NSWindow?
    private var settings: NSWindow?
    private var onboarding: NSWindow?
    private let shortcuts = ShortcutRegistry()
    private var observers: [NSObjectProtocol] = []
    private var localKeys: Any?
    private var quitting = false
    private var recoveryPresented = false
    private var subscriptions = Set<AnyCancellable>()
    init(fixtureMode: Bool, fixtureRecovery: Bool = false) { model = AppModel(fixtureMode: fixtureMode || fixtureRecovery, fixtureRecovery: fixtureRecovery); super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.onDismissPalette = { [weak self] in self?.dismissPalette() }
        model.onDismissOnboarding = { [weak self] in self?.onboarding?.orderOut(nil); self?.showPalette() }
        model.onTestShortcuts = { [weak self] in self?.showPalette() }
        model.$captureState.sink { [weak self] _ in self?.refreshMenu() }.store(in: &subscriptions)
        model.$recoveryMessage.sink { [weak self] message in
            guard let self else { return }
            if message == nil {
                guard self.recoveryPresented else { return }
                self.recoveryPresented = false
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, self.model.recoveryMessage == nil, !self.model.state.settings.onboardingComplete else { return }
                    self.dismissPalette(); self.showOnboarding()
                }
                return
            }
            self.recoveryPresented = true
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.model.recoveryMessage != nil else { return }
                self.onboarding?.orderOut(nil)
                self.showPalette()
            }
        }.store(in: &subscriptions)
        model.onShowLibrary = { [weak self] in self?.showLibrary() }
        model.onShowSettings = { [weak self] in self?.showSettings() }
        shortcuts.onPalette = { [weak self] in self?.showPalette() }
        shortcuts.onNext = { [weak self] in self?.model.nextInQueue() }
        configureShortcuts()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Winnel")
        item.button?.toolTip = "Winnel clipboard history"
        statusItem = item; refreshMenu()
        model.onSettingsChanged = { [weak self] _ in self?.configureShortcuts(); self?.refreshMenu() }
        setupLifecycle()
        observers.append(NotificationCenter.default.addObserver(forName: .winnelShortcutsChanged, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.configureShortcuts() } })
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated {
                if keyCode == 53 {
                    self?.model.cancelQueue()
                    if self?.panel?.isKeyWindow == true, self?.panel?.attachedSheet == nil { self?.dismissPalette(); return true }
                }
                return false
            }
            return handled ? nil : event
        }
        Task {
            await model.start()
            if model.recoveryMessage != nil { showPalette() }
            else if !model.state.settings.onboardingComplete { showOnboarding() }
            configureShortcuts(); refreshMenu()
        }
    }
    private func configureShortcuts() {
        let configuration = model.state.settings
        let palette = ShortcutSpec(keyCode: configuration.paletteShortcutKeyCode, modifiers: configuration.paletteShortcutModifiers)
        let next = ShortcutSpec(keyCode: configuration.nextShortcutKeyCode, modifiers: configuration.nextShortcutModifiers)
        if !shortcuts.configure(palette: palette, next: next), let error = shortcuts.error { model.status = error }
    }
    func refreshMenu() {
        let menu = NSMenu()
        add("Open Winnel", action: #selector(openPalette), to: menu)
        add("Saved Stacks", action: #selector(openLibrary), to: menu)
        menu.addItem(.separator())
        add(model.captureState == .active ? "Pause Capture" : "Resume Capture", action: #selector(toggleCapture), to: menu)
        add("Settings…", action: #selector(openSettings), to: menu)
        menu.addItem(.separator()); add("Quit Winnel", action: #selector(quit), to: menu)
        statusItem?.menu = menu
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    @objc private func openPalette() { showPalette() }
    @objc private func openLibrary() { showLibrary() }
    @objc private func openSettings() { showSettings() }
    @objc private func toggleCapture() { if model.captureState == .active { model.pause(until: nil) } else if !model.state.settings.captureEnabled { model.enableCapture() } else { model.resumeCapture() }; refreshMenu() }
    @objc private func quit() { NSApp.terminate(nil) }
    func showPalette() {
        model.capturePaletteTarget()
        if panel == nil {
            let storedSize = UserDefaults.standard.string(forKey: "paletteSize").map(NSSizeFromString) ?? NSSize(width: 620, height: 520)
            let size = NSSize(width: max(620, min(storedSize.width, 1000)), height: max(420, min(storedSize.height, 900)))
            let window = PalettePanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.contentMinSize = NSSize(width: 620, height: 420)
            window.title = "Winnel"; window.level = .floating; window.isFloatingPanel = true
            window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false; window.isRestorable = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: PaletteView(model: model)); window.delegate = self; window.center(); panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
    }
    func dismissPalette() { panel?.orderOut(nil) }
    func showLibrary() { dismissPalette(); if library == nil { library = makeWindow(title: "Saved Stacks", size: .init(width: 960, height: 680), view: LibraryView(model: model)) }; NSApp.activate(ignoringOtherApps: true); library?.makeKeyAndOrderFront(nil) }
    func showSettings() { dismissPalette(); if settings == nil { settings = makeWindow(title: "Winnel Settings", size: .init(width: 720, height: 700), view: SettingsView(model: model)) }; NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil) }
    func showOnboarding() { if onboarding == nil { onboarding = makeWindow(title: "Welcome to Winnel", size: .init(width: 680, height: 580), view: OnboardingView(model: model)) }; NSApp.activate(ignoringOtherApps: true); onboarding?.makeKeyAndOrderFront(nil) }
    private func makeWindow<V: View>(title: String, size: NSSize, view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.contentView = NSHostingView(rootView: view); window.isReleasedWhenClosed = false; window.isRestorable = false; window.center(); return window
    }
    func windowDidResize(_ notification: Notification) { if let window = notification.object as? NSWindow, window === panel { UserDefaults.standard.set(NSStringFromSize(window.contentLayoutRect.size), forKey: "paletteSize") } }
    private func setupLifecycle() {
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.handleLifecycleSuspension(); self?.dismissPalette(); self?.refreshMenu() } })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.resumeAfterWake(); self?.refreshMenu() } })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.handleLifecycleSuspension(); self?.dismissPalette() } })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.resumeAfterWake(); self?.refreshMenu() } })
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateNow }; quitting = true; shortcuts.unregister()
        Task { await model.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }; return .terminateLater
    }
}
