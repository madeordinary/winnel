import XCTest
@testable import WinnelCore
final class PolicyTests: XCTestCase {
    private func target() -> PasteTarget { .init(bundleIdentifier: "synthetic.editor", processIdentifier: 12, windowIdentifier: "window", controlIdentifier: "field") }
    private func decision(_ expected: PasteTarget?, _ current: PasteTarget?, permission: Bool = true, focusChanged: Bool = false) -> PasteDecision { PastePolicy.evaluate(enabled: true, accessibilityGranted: permission, expected: expected, current: current, supportedBundleIdentifiers: ["synthetic.editor"], competingFocusChange: focusChanged) }
    func testChangedProcessControlAndCompetingFocusFailClosed() {
        let original = target(); var changed = original; changed.processIdentifier = 13; XCTAssertEqual(decision(original, changed), .copy(.changedTarget))
        changed = original; changed.controlIdentifier = "other"; XCTAssertEqual(decision(original, changed), .copy(.changedTarget))
        XCTAssertEqual(decision(original, original, focusChanged: true), .copy(.changedTarget)); XCTAssertEqual(decision(original, original), .dispatch)
    }
    func testSecureTerminalAmbiguousAndRevocationFailClosed() {
        let original = target(); var unsafe = original; unsafe.isSecure = true; XCTAssertEqual(decision(unsafe, unsafe), .copy(.secure))
        unsafe = original; unsafe.isTerminal = true; XCTAssertEqual(decision(unsafe, unsafe), .copy(.terminal))
        unsafe = original; unsafe.controlIdentifier = nil; XCTAssertEqual(decision(unsafe, unsafe), .copy(.ambiguous))
        XCTAssertEqual(decision(original, original, permission: false), .copy(.permissionDenied))
    }
    func testExcludedTransitionAndPauseNeverCapture() {
        XCTAssertFalse(CapturePolicy.permits(enabled: true, paused: false, lifecycleActive: true, source: .init(), foregroundBundleIdentifier: "safe", previousForegroundBundleIdentifier: "excluded", excluded: ["excluded"]))
        XCTAssertFalse(CapturePolicy.permits(enabled: true, paused: true, lifecycleActive: true, source: .init(), foregroundBundleIdentifier: nil, previousForegroundBundleIdentifier: nil, excluded: []))
    }
}
