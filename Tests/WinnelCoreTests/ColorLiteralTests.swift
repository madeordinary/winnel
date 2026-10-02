import XCTest
import WinnelCore

final class ColorLiteralTests: XCTestCase {
    func testShortAndSixDigitLiteralsHaveIdenticalSRGBChannels() throws {
        let short = try XCTUnwrap(ColorLiteral(hexLiteral: "#aB3"))
        XCTAssertEqual(short, ColorLiteral(hexLiteral: "#AAbb33"))
        XCTAssertEqual(short.red, 170.0 / 255)
        XCTAssertEqual(short.green, 187.0 / 255)
        XCTAssertEqual(short.blue, 51.0 / 255)
        XCTAssertEqual(short.alpha, 1)
        XCTAssertEqual(ColorLiteral(hexLiteral: "#000")?.red, 0)
        XCTAssertEqual(ColorLiteral(hexLiteral: "#ffffff")?.blue, 1)
    }

    func testEightDigitsUseTrailingAlphaAndOnlySurroundingWhitespaceIsTrimmed() throws {
        let color = try XCTUnwrap(ColorLiteral(hexLiteral: " \n\t#12Ab3480\r\n"))
        XCTAssertEqual(color.red, 18.0 / 255)
        XCTAssertEqual(color.green, 171.0 / 255)
        XCTAssertEqual(color.blue, 52.0 / 255)
        XCTAssertEqual(color.alpha, 128.0 / 255)
        XCTAssertEqual(ColorLiteral(hexLiteral: "#12345600")?.alpha, 0)
        XCTAssertEqual(ColorLiteral(hexLiteral: "#123456FF")?.alpha, 1)
    }

    func testRejectsIncompleteInvalidAndInferredColors() {
        for text in ["", "#", "#12", "#1234", "#12345", "#1234567", "#123456789", "#GG0000", "123456", "0x123456", "red", "rgb(1, 2, 3)", "Use #123456", "#123456 and #abcdef", "#12 3456", "#１２３", "#123456\u{202E}"] {
            XCTAssertNil(ColorLiteral(hexLiteral: text), "Must not recognize \(text.debugDescription)")
        }
    }
}
