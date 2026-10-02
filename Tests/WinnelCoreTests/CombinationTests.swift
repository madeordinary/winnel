import XCTest
@testable import WinnelCore
final class CombinationTests: XCTestCase {
    private func entry(_ text: String, kind: ClipKind = .text, url: String? = nil) -> CombinationEntry {
        .init(item: .init(copiedAt: Date(), kind: kind, textPreview: text, payloadByteCount: text.utf8.count, fingerprint: text), payload: .init(representations: [.init(type: "public.utf8-plain-text", data: Data(text.utf8))]), associatedURL: url)
    }
    func testExactOrderedPreviewAndJSONEscaping() throws {
        let entries = [entry("a\"b"), entry("line\nnext")]
        XCTAssertEqual(try Combination.preview(entries, format: .newline), "a\"b\nline\nnext")
        XCTAssertEqual(try Combination.preview(entries, format: .bullets), "- a\"b\n- line\n  next")
        let json = try Combination.preview(entries, format: .jsonArray)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(json.utf8)), ["a\"b", "line\nnext"])
    }
    func testLinksRequireExplicitCitationAndEscapeLabels() throws {
        XCTAssertThrowsError(try Combination.preview([entry("excerpt")], format: .markdownLinks))
        XCTAssertEqual(try Combination.preview([entry("[title]", url: "https://example.com/a(b)")], format: .markdownLinks), "- [\\[title\\]](https://example.com/a%28b%29)")
        XCTAssertThrowsError(try Combination.preview([entry("run", url: "javascript:alert(1)")], format: .markdownLinks))
    }
    func testMixedSelectionFailsRatherThanDiscardingImage() {
        XCTAssertThrowsError(try Combination.preview([entry("text"), entry("image", kind: .image)], format: .newline)) { XCTAssertEqual($0 as? CombinationError, .unsupportedSelection) }
    }
}
