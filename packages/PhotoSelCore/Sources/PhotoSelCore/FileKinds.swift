import Foundation

/// File extensions the app understands (lowercase, without the dot).
/// Port of `ImageLoader::rawExtensions/imageExtensions` of the Qt app.
public enum FileKinds {
    public static let rawExtensions: Set<String> = [
        "arw", "srf", "sr2", "cr2", "cr3", "crw", "nef", "nrw", "raf", "orf",
        "rw2", "dng", "pef", "srw", "x3f", "3fr", "iiq", "erf", "kdc",
    ]
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "webp", "bmp", "gif", "heic", "heif",
    ]
    public static let jpegExtensions: Set<String> = ["jpg", "jpeg"]
    public static let sidecar = "xmp"

    public static func isRaw(_ ext: String) -> Bool { rawExtensions.contains(ext.lowercased()) }
    public static func isJPEG(_ ext: String) -> Bool { jpegExtensions.contains(ext.lowercased()) }
    public static func isSupported(_ ext: String) -> Bool {
        let e = ext.lowercased()
        return rawExtensions.contains(e) || imageExtensions.contains(e)
    }

    /// Which file of a photo is shown: JPG first (or RAW first with `preferRaw`).
    /// Lower is better.
    public static func displayRank(_ ext: String, preferRaw: Bool) -> Int {
        let raw = isRaw(ext)
        if preferRaw { return raw ? 0 : (isJPEG(ext) ? 1 : 2) }
        return isJPEG(ext) ? 0 : (raw ? 2 : 1)
    }

    /// Extensions of a folder in display order: JPG, other images, RAW, XMP last.
    public static func sorted<S: Sequence>(_ exts: S) -> [String] where S.Element == String {
        func rank(_ e: String) -> Int { e == sidecar ? 9 : displayRank(e, preferRaw: false) }
        return Array(Set(exts)).sorted { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a < b
        }
    }

    /// "ARW" -> "RAW (ARW)", "jpg" -> "JPG", "xmp" -> "XMP (valutazioni)".
    public static func label(_ ext: String) -> String {
        let up = ext.uppercased()
        if ext == sidecar { return "XMP (valutazioni)" }
        if isRaw(ext) { return "RAW (\(up))" }
        return up
    }
}
