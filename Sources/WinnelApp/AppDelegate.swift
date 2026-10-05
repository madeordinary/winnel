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
        NSApp.mainMenu = makeMainMenu()
        model.onDismissPalette = { [weak self] in self?.dismissPalette() }
        model.onDismissOnboarding = { [weak self] in self?.onboarding?.orderOut(nil); self?.showPalette() }
        model.onTestShortcuts = { [weak self] in self?.showPalette() }
        // @Published emits before the new value is stored; refresh on the next main-queue turn.
        model.$captureState.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshMenu() }.store(in: &subscriptions)
        model.$queue.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshMenu() }.store(in: &subscriptions)
        model.$lifecycleSuspended.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshMenu() }.store(in: &subscriptions)
        // Turning capture off changes the saved setting after the monitor state has already published.
        model.$state.map(\.settings.captureEnabled).removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshMenu() }.store(in: &subscriptions)
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
        item.button?.imagePosition = .imageLeading
        statusItem = item; refreshMenu()
        model.onSettingsChanged = { [weak self] _ in self?.configureShortcuts(); self?.refreshMenu() }
        setupLifecycle()
        observers.append(NotificationCenter.default.addObserver(forName: .winnelShortcutsChanged, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.configureShortcuts() } })
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated {
                guard keyCode == 53, let self else { return false }
                // Escape cancels the queue only from a surface that shows it; sheets and
                // Settings keep their own Escape behavior.
                let key = NSApp.keyWindow
                if let key, key === self.panel || key === self.library, key.attachedSheet == nil { self.model.cancelQueue() }
                if self.panel?.isKeyWindow == true, self.panel?.attachedSheet == nil { self.dismissPalette(); return true }
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
    /// The menu bar stays hidden for this accessory app, but text fields rely on these
    /// key equivalents for standard editing. Quit remains in the status menu only.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title); items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.submenu = menu; main.addItem(item)
        }
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = modifiers; item.target = target; return item
        }
        submenu("Winnel", [item("Settings…", #selector(openSettings), ",", target: self)])
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"), item("Redo", Selector(("redo:")), "z", [.command, .shift]), .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"), item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"), item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        submenu("Window", [item("Close", #selector(NSWindow.performClose(_:)), "w")])
        return main
    }
    private func configureShortcuts() {
        let configuration = model.state.settings
        let palette = ShortcutSpec(keyCode: configuration.paletteShortcutKeyCode, modifiers: configuration.paletteShortcutModifiers)
        let next = ShortcutSpec(keyCode: configuration.nextShortcutKeyCode, modifiers: configuration.nextShortcutModifiers)
        if !shortcuts.configure(palette: palette, next: next), let error = shortcuts.error { model.status = error }
        model.activeNextShortcut = shortcuts.activeNext?.displayName; refreshMenu()
    }
    func refreshMenu() {
        let menu = NSMenu()
        // Explicit isEnabled values below must not be overridden by automatic validation.
        menu.autoenablesItems = false
        let state = model.captureState
        if let queue = model.queue {
            let count = queue.entries.count, position = min(queue.position + 1, count)
            let next = model.activeNextShortcut.map { " (\($0))" } ?? ""
            info(queue.isComplete ? (queue.mode == .copy ? "Queue complete: \(count) items copied" : "Queue complete: \(count) paste requests sent") : "Queue \(position) of \(count): " + WinnelStyle.displayText(String((queue.current?.item.textPreview ?? "").prefix(40))), to: menu)
            add(queue.mode == .copy ? "Copy Next Item" + next : "Paste Next Item" + next, action: #selector(queueNext), to: menu).isEnabled = queue.current != nil
            add("Back", action: #selector(queueBack), to: menu).isEnabled = queue.position > 0
            add("Cancel Queue", action: #selector(queueCancel), to: menu)
            menu.addItem(.separator())
        }
        add("Open Winnel", action: #selector(openPalette), to: menu)
        add("Saved Stacks", action: #selector(openLibrary), to: menu)
        menu.addItem(.separator())
        info(state.label, to: menu)
        if model.lifecycleSuspended { add("Resume After Lock or Sleep", action: #selector(resumeFromSuspension), to: menu) }
        if !model.state.settings.captureEnabled { add("Turn On Capture", action: #selector(toggleCapture), to: menu) }
        else if !model.lifecycleSuspended { add(state == .active ? "Pause Capture" : "Resume Capture", action: #selector(toggleCapture), to: menu) }
        add("Settings…", action: #selector(openSettings), to: menu)
        menu.addItem(.separator()); add("Quit Winnel", action: #selector(quit), to: menu)
        statusItem?.menu = menu
        // The symbol is slashed whenever new copies are not being recorded.
        let symbol = state == .active ? "square.stack.3d.up" : "square.stack.3d.up.slash"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Winnel, " + state.label)
        statusItem?.button?.title = model.queue.map { $0.isComplete ? " ✓" : " \(min($0.position + 1, $0.entries.count))/\($0.entries.count)" } ?? ""
        statusItem?.button?.toolTip = "Winnel clipboard history — " + state.label
    }
    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item); return item }
    private func info(_ title: String, to menu: NSMenu) { let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
    @objc private func queueNext() { model.nextInQueue() }
    @objc private func resumeFromSuspension() { model.endSuspensionFromUser() }
    @objc private func queueBack() { model.backInQueue() }
    @objc private func queueCancel() { model.cancelQueue() }
    @objc private func openPalette() { showPalette() }
    @objc private func openLibrary() { showLibrary() }
    @objc private func openSettings() { showSettings() }
    @objc private func toggleCapture() { if !model.state.settings.captureEnabled { model.enableCapture() } else if model.captureState == .active { model.pause(until: nil) } else { model.resumeCaptureFromUser() } }
    @objc private func quit() { NSApp.terminate(nil) }
    func showPalette() {
        guard NSApp.modalWindow == nil else { return }
        model.capturePaletteTarget()
        // Only a fresh opening starts a new session. Re-focusing a visible palette, or opening it
        // while a sheet still depends on the shared selection, keeps the user's query and selection.
        let inFront = panel?.isVisible == true && panel?.isOnActiveSpace == true
        if !inFront, panel?.attachedSheet == nil, library?.attachedSheet == nil { model.prepareForPaletteOpen() }
        else { model.requestPaletteFocus() }
        if panel == nil {
            let storedSize = UserDefaults.standard.string(forKey: "paletteSize").map(NSSizeFromString) ?? NSSize(width: 760, height: 600)
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
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.handleLifecycleSuspension(screenLocked: true); self?.dismissPalette() } })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.handleScreenUnlocked(); self?.refreshMenu() } })
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateNow }; quitting = true; shortcuts.unregister()
        Task { await model.shutdown(); NSApp.reply(toApplicationShouldTerminate: true) }; return .terminateLater
    }
}
