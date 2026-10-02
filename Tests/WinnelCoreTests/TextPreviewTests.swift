import XCTest
@testable import WinnelCore

final class TextPreviewTests: XCTestCase {
    func testPreviewCapsBytesWithoutChangingCopiedPayload() throws {
        let text = String(repeating: "x", count: 100_000)
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data(text.utf8))])
        let preview = try XCTUnwrap(payload.boundedPlainText())
        XCTAssertEqual(preview.text.utf8.count, 65_536)
        XCTAssertTrue(preview.isTruncated)
        XCTAssertEqual(payload.plainText, text)
    }
    func testPreviewNeverSplitsUTF8ScalarAtBound() throws {
        let payload = ClipPayload(representations: [.init(type: "public.utf8-plain-text", data: Data("abc🙂tail".utf8))])
        for bound in 4...6 {
            let preview = try XCTUnwrap(payload.boundedPlainText(maximumUTF8Bytes: bound))
            XCTAssertEqual(preview.text, "abc"); XCTAssertTrue(preview.isTruncated)
        }
        XCTAssertEqual(payload.boundedPlainText(maximumUTF8Bytes: 7)?.text, "abc🙂")
        XCTAssertNil(payload.boundedPlainText(maximumUTF8Bytes: 0))
    }
    func testSmallURLPreviewIsComplete() throws {
        let text = "https://example.invalid/fixture"
        let payload = ClipPayload(representations: [.init(type: "public.url", data: Data(text.utf8))])
        let preview = try XCTUnwrap(payload.boundedPlainText())
        XCTAssertEqual(preview.text, text); XCTAssertFalse(preview.isTruncated)
    }
}
