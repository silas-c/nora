import Foundation

/// WCAG 2.2 relative luminance and contrast ratio for sRGB colors written as 0xRRGGBB.
public enum WCAG {
    public static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (first, second) = (relativeLuminance(a), relativeLuminance(b))
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

/// Status colors, each with a light-appearance and dark-appearance variant.
public enum Palette {
    public struct Pair: Sendable {
        public var light: UInt32
        public var dark: UInt32
    }

    public static let success = Pair(light: 0x1B7A3A, dark: 0x5BD17E)
    public static let failure = Pair(light: 0xB3261E, dark: 0xFF8A80)
    public static let attention = Pair(light: 0x8A5300, dark: 0xFFC266)
    public static let info = Pair(light: 0x1E4FA3, dark: 0x8AB4F8)
    public static let all = [success, failure, attention, info]

    public static let lightBackground: UInt32 = 0xFFFFFF
    public static let darkBackground: UInt32 = 0x1E1E1E
    public static let scanHighlight: UInt32 = 0xFFD60A
}
