import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Carbon

public enum PasteDispatchResult: String, Sendable { case dispatched, manualFallback }
public struct PasteCompatibilityRule: Sendable {
    public var bundleIdentifier: String
    public var role: String
    public var testedAppVersion: String?
    public var testedAppBuild: String?
    public init(bundleIdentifier: String, role: String, testedAppVersion: String? = nil, testedAppBuild: String? = nil) {
        self.bundleIdentifier = bundleIdentifier; self.role = role
        self.testedAppVersion = testedAppVersion; self.testedAppBuild = testedAppBuild
    }
    public func matches(bundle: String, role: String, version: String?, build: String?) -> Bool {
        testedAppVersion != nil && testedAppBuild != nil && bundleIdentifier == bundle && self.role == role && testedAppVersion == version && testedAppBuild == build
    }
}
/// Any observed destination change is irreversible for this invocation, even if it returns.
@MainActor final class TargetObservationState {
    private(set) var changed = false
    func invalidate() { changed = true }
}
@MainActor private final class TargetAXObservation {
    let state = TargetObservationState()
    private var observer: AXObserver?
    private var registrations: [(AXUIElement, String)] = []
    init?(pid: pid_t, application: AXUIElement) {
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<TargetAXObservation>.fromOpaque(context).takeUnretainedValue().state.invalidate()
            }
        }, &created) == .success, let created else { return nil }
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        guard register(application, kAXFocusedUIElementChangedNotification), register(application, kAXFocusedWindowChangedNotification) else { return nil }
    }
    func register(_ element: AXUIElement, _ notification: String) -> Bool {
        guard let observer, AXObserverAddNotification(observer, element, notification as CFString, Unmanaged.passUnretained(self).toOpaque()) == .success else { return false }
        registrations.append((element, notification)); return true
    }
    isolated deinit {
        if let observer {
            for (element, notification) in registrations { AXObserverRemoveNotification(observer, element, notification as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
@MainActor public final class PasteTarget {
    fileprivate var invalidated = false
    fileprivate var observation: TargetAXObservation?
    fileprivate let pid: pid_t
    fileprivate let launchDate: Date
    fileprivate var appVersion: String?
    fileprivate var appBuild: String?
    fileprivate let bundleID: String
    fileprivate let window: AXUIElement
    fileprivate let element: AXUIElement
    fileprivate let selectedRange: AXValue
    fileprivate init(pid: pid_t, launchDate: Date, bundleID: String, window: AXUIElement, element: AXUIElement, selectedRange: AXValue) { self.pid = pid; self.launchDate = launchDate; self.bundleID = bundleID; self.window = window; self.element = element; self.selectedRange = selectedRange }
}
@MainActor public final class PasteTargetService {
    /// Remains empty until a particular app/control has observed integration evidence.
    private weak var pending: PasteTarget?
    private var activationObserver: NSObjectProtocol?
    private var activationGeneration = 0
    public var compatibilityRules: [PasteCompatibilityRule]
    public init(compatibilityRules: [PasteCompatibilityRule] = []) {
        self.compatibilityRules = compatibilityRules
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                self?.activationGeneration += 1
                guard let target = self?.pending, let pid = activatedPID else { return }
                if pid != target.pid { target.invalidated = true }
            }
        }
    }
    isolated deinit {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
    public var hasPermission: Bool { AXIsProcessTrusted() }
    /// Call only in response to the user's explicit Enable Direct Paste action.
    public func requestPermissionFromUserAction() -> Bool { AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? { var result: CFTypeRef?; return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil }
    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    private func rangeAttribute(_ element: AXUIElement) -> AXValue? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
    public func captureTarget() -> PasteTarget? {
        pending?.invalidated = true; pending = nil
        let activationEpoch = activationGeneration
        guard hasPermission, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundle = app.bundleIdentifier, let launch = app.launchDate,
              !["com.apple.Terminal", "com.googlecode.iterm2"].contains(bundle),
              compatibilityRules.contains(where: { $0.bundleIdentifier == bundle }) else { return nil }
        guard let appURL = app.bundleURL, let appBundle = Bundle(url: appURL) else { return nil }
        let version = appBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = appBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        guard let observation = TargetAXObservation(pid: app.processIdentifier, application: application) else { return nil }
        guard let focused = elementAttribute(application, kAXFocusedUIElementAttribute),
              let window = elementAttribute(application, kAXFocusedWindowAttribute),
              let role = attribute(focused, kAXRoleAttribute) as? String,
              let subrole = attribute(focused, kAXSubroleAttribute) as? String,
              subrole != kAXSecureTextFieldSubrole,
              compatibilityRules.contains(where: { $0.matches(bundle: bundle, role: role, version: version, build: build) }),
              observation.register(focused, kAXSelectedTextChangedNotification),
              let range = rangeAttribute(focused), AXValueGetType(range) == .cfRange,
              let settledFocus = elementAttribute(application, kAXFocusedUIElementAttribute), CFEqual(settledFocus, focused),
              let settledWindow = elementAttribute(application, kAXFocusedWindowAttribute), CFEqual(settledWindow, window),
              let settledRange = rangeAttribute(focused), CFEqual(settledRange, range),
              !observation.state.changed, activationGeneration == activationEpoch,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return nil }
        let target = PasteTarget(pid: app.processIdentifier, launchDate: launch, bundleID: bundle, window: window, element: focused, selectedRange: range)
        target.appVersion = version; target.appBuild = build
        target.observation = observation
        pending = target
        return target
    }
    private func supportedKeyboardLayout() -> Bool {
        guard let input = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(input, kTISPropertyInputSourceID) else { return false }
        let identifier = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return ["com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.British"].contains(identifier)
    }
    /// Waits briefly for the invoking shortcut to be released without changing the saved
    /// destination. The caller's action/queue token must remain current throughout the wait.
    public func waitForModifiersThenDispatch(to target: PasteTarget, isCurrent: @MainActor () -> Bool) async -> PasteDispatchResult {
        guard await Self.waitUntilReady(isCurrent: isCurrent, isReady: { Self.modifiersReleased() }) else { return .manualFallback }
        // Give already queued AX notifications a main-run-loop turn before final checks.
        do { try await Task.sleep(for: .milliseconds(20)) } catch { return .manualFallback }
        guard !Task.isCancelled, isCurrent(), target.observation?.state.changed == false else { return .manualFallback }
        return dispatchPaste(to: target, isCurrent: isCurrent)
    }
    /// Injectable readiness keeps synthetic tests independent of AX consent and real input.
    public static func waitUntilReady(isCurrent: @MainActor () -> Bool, isReady: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while true {
            guard !Task.isCancelled, isCurrent(), ContinuousClock.now < deadline else { return false }
            if isReady() { return !Task.isCancelled && isCurrent() }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
        }
    }
    private static func modifiersReleased() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }
    private func matchesCurrent(_ target: PasteTarget) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == target.pid,
              app.launchDate == target.launchDate, app.bundleIdentifier == target.bundleID,
              let url = app.bundleURL, let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == target.appVersion,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == target.appBuild else { return false }
        let application = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        guard let focused = elementAttribute(application, kAXFocusedUIElementAttribute), CFEqual(focused, target.element),
              let window = elementAttribute(application, kAXFocusedWindowAttribute), CFEqual(window, target.window),
              let range = rangeAttribute(focused), CFEqual(range, target.selectedRange),
              let role = attribute(focused, kAXRoleAttribute) as? String,
              let subrole = attribute(focused, kAXSubroleAttribute) as? String, subrole != kAXSecureTextFieldSubrole,
              compatibilityRules.contains(where: { $0.matches(bundle: target.bundleID, role: role, version: target.appVersion, build: target.appBuild) }) else { return false }
        return true
    }
    /// Focus restoration is owned by the panel. This method never activates or chases a target.
    private func dispatchPaste(to target: PasteTarget, isCurrent: @MainActor () -> Bool) -> PasteDispatchResult {
        guard !IsSecureEventInputEnabled(), Self.modifiersReleased(), supportedKeyboardLayout(), !target.invalidated, target.observation?.state.changed == false, hasPermission, matchesCurrent(target),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return .manualFallback }
        guard !target.invalidated, target.observation?.state.changed == false, isCurrent() else { return .manualFallback }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.postToPid(target.pid); up.postToPid(target.pid)
        // Event dispatch does not establish that the destination consumed the clipboard.
        return .dispatched
    }
}
