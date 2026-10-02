import XCTest
@testable import WinnelPlatform
final class UpdateTests: XCTestCase {
    func metadata(_ tag: String, url: String = "https://github.com/madeordinary/winnel/releases/tag/v0.2.0", draft: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url, "draft": draft, "prerelease": false])
    }
    func testVersionsComparedNumericallyAndOnlyStableOfficialLinks() throws {
        XCTAssertEqual(try UpdateChecker.parse(metadata("v0.1.0"), currentVersion: "0.1.0"), .current)
        guard case .available = try UpdateChecker.parse(metadata("v0.10.0"), currentVersion: "0.9.0") else { return XCTFail("Expected newer numeric version") }
        XCTAssertThrowsError(try UpdateChecker.parse(metadata("v0.2.0", url: "https://evil.example/release"), currentVersion: "0.1.0"))
        XCTAssertThrowsError(try UpdateChecker.parse(metadata("v0.2.0", draft: true), currentVersion: "0.1.0"))
        XCTAssertThrowsError(try UpdateChecker.parse(metadata("v0.2.0-beta"), currentVersion: "0.1.0"))
    }
}
