import Foundation

/// A "photo" is the group of files with the same base name:
/// DSC01234.JPG + DSC01234.ARW (+ DSC01234.xmp) = one photo.
public struct Photo: Identifiable, Equatable, Sendable {
    /// Position in chronological order; stable until the folder is read again.
    public var uid: Int = -1
    public var id: Int { uid }
    public var baseName: String
    public var folder: URL
    /// lowercase extension -> file URL (includes "xmp" when the sidecar exists)
    public var files: [String: URL] = [:]
    public var totalBytes: Int64 = 0

    /// Extension of the file that is shown.
    public var displayExt: String = ""
    public var pixelWidth = 0
    public var pixelHeight = 0

    public var exif = ExifInfo()
    /// Capture time, or modification date of the displayed file.
    public var sortTime: Date = .distantPast

    // Rating
    public var stars = 0   // 0...5
    public var flag = 0    // 1 kept, -1 rejected
    public var label = 0   // 0...5

    // View only (session)
    public var rotation = 0  // 0, 90, 180, 270

    // Bursts
    public var burstId = -1
    public var burstIndex = 0
    public var burstSize = 1

    // Background analysis
    public var analyzed = false
    public var sharpness: Double = 0
    public var histogram: [Float] = []

    public init(baseName: String, folder: URL) {
        self.baseName = baseName
        self.folder = folder
    }

    public var displayURL: URL? { files[displayExt] }
    public var displayFileName: String { displayURL?.lastPathComponent ?? baseName }
    public var hasRaw: Bool { files.keys.contains { FileKinds.isRaw($0) } }
    public var isBurst: Bool { burstSize > 1 }

    /// The sidecar path, whether it exists or not.
    public var xmpURL: URL {
        files[FileKinds.sidecar] ?? folder.appendingPathComponent(baseName + ".xmp")
    }

    /// Image files other than the shown one, e.g. the RAW next to the JPG.
    public var rawURL: URL? {
        files.first { FileKinds.isRaw($0.key) }?.value
    }

    /// ["JPG", "ARW", "XMP"]: the shown format first, then the others.
    public var extensionBadges: [String] {
        let others = FileKinds.sorted(files.keys.filter { $0 != displayExt })
        return ([displayExt] + others).filter { !$0.isEmpty }.map { $0.uppercased() }
    }

    /// Pixel size of the shown file; for RAW files the preview decides.
    public var dimensionsText: String {
        let w = pixelWidth > 0 ? pixelWidth : exif.width
        let h = pixelHeight > 0 ? pixelHeight : exif.height
        return ItalianFormat.dimensions(width: w, height: h)
    }
}
