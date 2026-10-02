import Foundation

/// A complete #RGB, #RRGGBB or #RRGGBBAA literal; never infers colors from prose.
public struct ColorLiteral: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init?(hexLiteral text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("#"), [4, 7, 9].contains(value.count) else { return nil }
        var digits = String(value.dropFirst())
        guard digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        if digits.count == 3 { digits = digits.map { String(repeating: String($0), count: 2) }.joined() }
        guard let number = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let shift = hasAlpha ? 8 : 0
        red = Double((number >> (16 + shift)) & 255) / 255
        green = Double((number >> (8 + shift)) & 255) / 255
        blue = Double((number >> shift) & 255) / 255
        alpha = hasAlpha ? Double(number & 255) / 255 : 1
    }
}
