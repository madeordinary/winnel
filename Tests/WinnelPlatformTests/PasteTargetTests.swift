import XCTest
@testable import WinnelPlatform

final class PasteTargetTests: XCTestCase {
    @MainActor func testFocusAwayAndBackCannotRestoreValidity() {
        let observation = TargetObservationState()
        XCTAssertFalse(observation.changed)
        observation.invalidate() // focus/caret moved away
        observation.invalidate() // focus/caret returned
        XCTAssertTrue(observation.changed)
    }
    func testCompatibilityRequiresExactObservedVersionAndBuild() {
        let unobserved = PasteCompatibilityRule(bundleIdentifier: "synthetic.app", role: "AXTextArea")
        XCTAssertFalse(unobserved.matches(bundle: "synthetic.app", role: "AXTextArea", version: "1", build: "1"))
        let observed = PasteCompatibilityRule(bundleIdentifier: "synthetic.app", role: "AXTextArea", testedAppVersion: "1", testedAppBuild: "10")
        XCTAssertTrue(observed.matches(bundle: "synthetic.app", role: "AXTextArea", version: "1", build: "10"))
        XCTAssertFalse(observed.matches(bundle: "synthetic.app", role: "AXTextArea", version: "1", build: "11"))
        XCTAssertFalse(observed.matches(bundle: "synthetic.app", role: "AXTextField", version: "1", build: "10"))
    }
}
