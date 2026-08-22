import Foundation

/// A JSON value the protocol layers can hold, compare, and encode without
/// reaching for `Any`.
///
/// `JSONSerialization` would be shorter, but it hands back `Any`, which cannot
/// cross an actor boundary, cannot be compared in a test without casting, and
/// silently turns a `Bool` into an `NSNumber`. The protocol code here is the
/// part that must be exactly right, so it gets a type.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Accessors

    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }

    /// Every numeric accessor is total.
    ///
    /// These read values an untrusted client supplied, and `Int(1e300)` traps
    /// rather than returning anything — a crash an approved agent could cause
    /// with one malformed argument, taking unsaved work with it.
    public var intValue: Int? {
        switch self {
        case .int(let value): value
        case .double(let value) where value == value.rounded(): Int(exactly: value)
        default: nil
        }
    }

    /// A non-negative integer, for the revision and offset fields.
    ///
    /// `UInt64(someNegativeInt)` traps too, so the conversion is checked here
    /// once rather than at every call site that could forget.
    public var unsignedValue: UInt64? {
        guard let value = intValue, value >= 0 else { return nil }
        return UInt64(value)
    }

    /// A non-negative integer usable as an offset or length.
    public var offsetValue: Int? {
        guard let value = intValue, value >= 0 else { return nil }
        return value
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members[key]
    }

    // MARK: - Bridging

    public init(any value: Any) {
        switch value {
        case is NSNull: self = .null
        case let number as NSNumber:
            // `NSNumber` erases Bool into a number; the object identity check
            // is the only reliable way back.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if let exact = Int(exactly: number) {
                self = .int(exact)
            } else {
                self = .double(number.doubleValue)
            }
        case let text as String: self = .string(text)
        case let items as [Any]: self = .array(items.map(JSONValue.init(any:)))
        case let members as [String: Any]:
            self = .object(members.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    public var anyValue: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .int(let value): value
        case .double(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.anyValue)
        case .object(let members): members.mapValues(\.anyValue)
        }
    }

    public static func decode(_ data: Data) throws -> JSONValue {
        JSONValue(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    public func encoded(sortedKeys: Bool = true) throws -> Data {
        var options: JSONSerialization.WritingOptions = [.fragmentsAllowed]
        if sortedKeys { options.insert(.sortedKeys) }
        return try JSONSerialization.data(withJSONObject: anyValue, options: options)
    }

    public func encodedString(sortedKeys: Bool = true) throws -> String {
        String(decoding: try encoded(sortedKeys: sortedKeys), as: UTF8.self)
    }

    // MARK: - Construction helpers

    public static func of(_ pairs: [String: JSONValue?]) -> JSONValue {
        .object(pairs.compactMapValues { $0 })
    }
}
