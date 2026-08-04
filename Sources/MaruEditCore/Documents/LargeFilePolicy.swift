import Foundation

public enum LargeFileMode: String, Sendable, Codable, Equatable {
    case normal
    case reducedFeatures
    case readOnly

    public var usesReducedFeatures: Bool { self != .normal }
}

public enum LargeFileRecommendation: Sendable, Equatable {
    case normal
    case reducedFeatures
    case confirmationRequired
    case tooLarge
}

/// Thresholds are engineering defaults derived from the M0 measurements:
/// 1 MiB missed the 200 ms target by ~11x and 10 MiB missed the 1 s target
/// by ~13x. They are intentionally centralized so M7-08 can retune them.
public enum LargeFilePolicy {
    public static let reducedFeaturesThreshold: Int64 = 1 * 1_024 * 1_024
    public static let confirmationThreshold: Int64 = 10 * 1_024 * 1_024
    public static let maximumMaterializedSize: Int64 = 256 * 1_024 * 1_024

    public static func recommendation(forByteCount count: Int64) -> LargeFileRecommendation {
        if count > maximumMaterializedSize { return .tooLarge }
        if count >= confirmationThreshold { return .confirmationRequired }
        if count >= reducedFeaturesThreshold { return .reducedFeatures }
        return .normal
    }

    public static func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return Int64(size)
    }
}
