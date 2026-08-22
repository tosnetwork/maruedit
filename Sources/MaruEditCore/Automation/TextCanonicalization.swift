import Foundation

/// Canonical text form for everything the editor stores.
///
/// A document buffer holds LF only. Loading already normalized, but the
/// initializer, templates, macros, paste, drop, find/replace, and generated
/// documents did not, so a carriage return could reach text storage and break
/// the offset, digest, and line-index guarantees that everything above depends
/// on. Canonicalization therefore happens at every ingress, *before* the
/// mutation reaches storage — after it, offsets and undo state already reflect
/// the unnormalized text.
public enum TextCanonicalization {

    /// Converts CRLF and lone CR to LF. Returns the argument unchanged when it
    /// already contains no carriage return, so the common path allocates
    /// nothing.
    public static func canonical(_ text: String) -> String {
        containsCarriageReturn(text) ? LineEndingDetector.normalize(text) : text
    }

    public static func containsCarriageReturn(_ text: String) -> Bool {
        text.utf8.contains(0x0D)
    }

    /// True when `text` is already canonical.
    public static func isCanonical(_ text: String) -> Bool {
        !containsCarriageReturn(text)
    }
}
