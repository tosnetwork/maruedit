import Foundation

/// A stable, serializable text-encoding identifier (ROADMAP.md section
/// 9.3). Deliberately not a raw `String.Encoding` integer — those aren't
/// guaranteed stable across OS versions and aren't human-readable in a
/// saved session/preferences file.
public struct TextEncoding: RawRepresentable, Codable, Sendable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension TextEncoding {
    public static let utf8 = TextEncoding(rawValue: "UTF-8")
    public static let utf16LittleEndian = TextEncoding(rawValue: "UTF-16LE")
    public static let utf16BigEndian = TextEncoding(rawValue: "UTF-16BE")
    /// Microsoft's Shift-JIS variant (CP932). This is the common
    /// "Shift-JIS" encountered in real-world Japanese files — distinct
    /// from Apple's own `.shiftJIS`, which is the older, narrower
    /// classic Mac OS Japanese encoding (see `.shiftJISClassic`).
    public static let windows31J = TextEncoding(rawValue: "Windows-31J")
    /// The classic Mac OS Shift-JIS variant (`String.Encoding.shiftJIS`).
    /// Listed separately from `.windows31J` because they are genuinely
    /// different byte-level encodings that happen to share a common name.
    public static let shiftJISClassic = TextEncoding(rawValue: "Shift_JIS")
    public static let eucJP = TextEncoding(rawValue: "EUC-JP")
    public static let iso2022JP = TextEncoding(rawValue: "ISO-2022-JP")
    public static let ascii = TextEncoding(rawValue: "US-ASCII")

    /// All initial candidates considered by `EncodingDetector`, in the
    /// order they're offered as fallbacks per ROADMAP.md section 10.1.
    public static let initialCandidates: [TextEncoding] = [
        .windows31J, .shiftJISClassic, .eucJP, .iso2022JP
    ]

    public var displayName: String {
        switch self {
        case .utf8:             return "UTF-8"
        case .utf16LittleEndian: return "UTF-16 (Little Endian)"
        case .utf16BigEndian:    return "UTF-16 (Big Endian)"
        case .windows31J:        return "Windows-31J (Shift-JIS)"
        case .shiftJISClassic:   return "Shift-JIS (Classic Mac)"
        case .eucJP:             return "EUC-JP"
        case .iso2022JP:         return "ISO-2022-JP"
        case .ascii:             return "ASCII"
        default:                 return rawValue
        }
    }

    /// The underlying Foundation encoding used to actually decode/encode
    /// bytes. `nil` for identifiers this build doesn't know how to map to
    /// a concrete `String.Encoding` (forward-compatibility: a future
    /// schema might list an encoding this version can't handle yet).
    public var foundationEncoding: String.Encoding? {
        switch self {
        case .utf8:              return .utf8
        case .utf16LittleEndian: return .utf16LittleEndian
        case .utf16BigEndian:    return .utf16BigEndian
        case .eucJP:             return .japaneseEUC
        case .iso2022JP:         return .iso2022JP
        case .ascii:             return .ascii
        case .shiftJISClassic:   return .shiftJIS
        case .windows31J:
            let cfEncoding = CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            guard nsEncoding != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: nsEncoding)
        default:
            return nil
        }
    }
}
