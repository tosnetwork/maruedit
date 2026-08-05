import Foundation

public enum BinaryDocumentCodecError: Error, Equatable, LocalizedError {
    case invalidToken(String)

    public var errorDescription: String? {
        switch self {
        case .invalidToken(let token):
            return "Binary mode expects two-digit hexadecimal bytes separated by commas; invalid token: \(token)"
        }
    }
}

public enum BinaryDocumentCodec {
    public static func format(_ data: Data, bytesPerLine: Int = 16) -> String {
        guard !data.isEmpty else { return "" }
        let width = max(1, bytesPerLine)
        return stride(from: 0, to: data.count, by: width).map { offset in
            data[offset..<min(offset + width, data.count)]
                .map { String(format: "%02X", $0) }
                .joined(separator: ",")
        }.joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> Data {
        let tokens = text.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        var bytes: [UInt8] = []
        bytes.reserveCapacity(tokens.count)
        for tokenSlice in tokens {
            let token = String(tokenSlice)
            guard token.count == 2, let byte = UInt8(token, radix: 16) else {
                throw BinaryDocumentCodecError.invalidToken(token)
            }
            bytes.append(byte)
        }
        return Data(bytes)
    }
}
