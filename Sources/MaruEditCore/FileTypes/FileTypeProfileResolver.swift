import Foundation

public struct FileTypeProfileResolver: Sendable {
    public var profiles: [SourcedFileTypeProfile]
    public init(profiles: [SourcedFileTypeProfile]) { self.profiles = profiles }

    public func resolve(for url: URL) -> FileTypeProfile? {
        let filename = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        return profiles.compactMap { sourced -> (SourcedFileTypeProfile, Int)? in
            let exact = sourced.profile.filenamePatterns.contains { $0.lowercased() == filename }
            let extensionMatch = sourced.profile.extensions.contains {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() == ext
            }
            guard exact || extensionMatch || sourced.profile.id == "builtin.plainText" else { return nil }
            return (sourced, exact ? 2 : (extensionMatch ? 1 : 0))
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.source.rawValue != rhs.0.source.rawValue {
                return lhs.0.source.rawValue > rhs.0.source.rawValue
            }
            if lhs.0.profile.priority != rhs.0.profile.priority {
                return lhs.0.profile.priority > rhs.0.profile.priority
            }
            return lhs.0.profile.id < rhs.0.profile.id
        }.first?.0.profile
    }
}

public extension FileTypeProfileResolver {
    static var builtIn: FileTypeProfileResolver {
        FileTypeProfileResolver(profiles: BuiltInFileTypeProfiles.all.map {
            SourcedFileTypeProfile($0, source: .builtIn)
        })
    }
}
