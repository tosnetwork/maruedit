import Foundation
import MaruEditCore

/// Recently-used "Reopen with Encoding" choices (ROADMAP.md M2-02),
/// following the same `UserDefaults`-backed MRU-list pattern as
/// `RecentItems`.
enum RecentEncodings {
    private static let key = "RecentEncodings"
    private static let max = 5

    static var encodings: [TextEncoding] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).map { TextEncoding(rawValue: $0) }
    }

    static func add(_ encoding: TextEncoding) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == encoding.rawValue }
        list.insert(encoding.rawValue, at: 0)
        if list.count > max { list = Array(list.prefix(max)) }
        UserDefaults.standard.set(list, forKey: key)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
