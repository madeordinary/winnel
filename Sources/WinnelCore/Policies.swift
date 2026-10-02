import Foundation

public struct PasteTarget: Equatable, Sendable {
    public var bundleIdentifier: String
    public var processIdentifier: Int32
    public var windowIdentifier: String?
    public var controlIdentifier: String?
    public var isSecure: Bool
    public var isTerminal: Bool
    public var isAmbiguous: Bool
    public init(bundleIdentifier: String, processIdentifier: Int32, windowIdentifier: String?, controlIdentifier: String?, isSecure: Bool = false, isTerminal: Bool = false, isAmbiguous: Bool = false) { self.bundleIdentifier = bundleIdentifier; self.processIdentifier = processIdentifier; self.windowIdentifier = windowIdentifier; self.controlIdentifier = controlIdentifier; self.isSecure = isSecure; self.isTerminal = isTerminal; self.isAmbiguous = isAmbiguous }
}
public enum PasteFallbackReason: String, Sendable { case disabled, permissionDenied, missingTarget, unsupportedApp, secure, terminal, ambiguous, changedTarget }
public enum PasteDecision: Equatable, Sendable { case dispatch; case copy(PasteFallbackReason) }
public enum PastePolicy {
    public static func evaluate(enabled: Bool, accessibilityGranted: Bool, expected: PasteTarget?, current: PasteTarget?, supportedBundleIdentifiers: Set<String>, competingFocusChange: Bool = false) -> PasteDecision {
        guard enabled else { return .copy(.disabled) }
        guard accessibilityGranted else { return .copy(.permissionDenied) }
        guard let expected, let current else { return .copy(.missingTarget) }
        guard !current.isSecure && !expected.isSecure else { return .copy(.secure) }
        guard !current.isTerminal && !expected.isTerminal else { return .copy(.terminal) }
        guard !current.isAmbiguous && !expected.isAmbiguous, current.windowIdentifier != nil, current.controlIdentifier != nil else { return .copy(.ambiguous) }
        guard !competingFocusChange, expected == current else { return .copy(.changedTarget) }
        guard supportedBundleIdentifiers.contains(current.bundleIdentifier) else { return .copy(.unsupportedApp) }
        return .dispatch
    }
}
public enum CapturePolicy {
    public static func permits(enabled: Bool, paused: Bool, lifecycleActive: Bool, source: SourceApplication, foregroundBundleIdentifier: String?, previousForegroundBundleIdentifier: String?, excluded: Set<String>) -> Bool {
        guard enabled, !paused, lifecycleActive else { return false }
        let evidence = [source.bundleIdentifier, foregroundBundleIdentifier, previousForegroundBundleIdentifier].compactMap { $0 }
        guard !evidence.contains(where: { excluded.contains($0) }) else { return false }
        return true
    }
}
