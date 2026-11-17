import CryptoKit
import ImageIO
import PhotoSelCore
import UIKit
import UniformTypeIdentifiers

/// Image decoding with ImageIO (JPEG, HEIC, PNG, TIFF and the RAW formats the
/// system understands), at three levels like the Qt app: thumbnail (disk cache),
/// screen size (memory cache + preload of the neighbours) and full size (zoom).
final class ImageService: @unchecked Sendable {
    static let thumbEdge = 480

    enum Level: String { case thumb, screen, full }

    private let memory = NSCache<NSString, UIImage>()
    private let screens = NSCache<NSString, UIImage>()
    private let cacheDir: URL

    init() {
        memory.countLimit = 900
        screens.countLimit = 10
        cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Longest edge used for the "screen" level (set from the window size).
    var screenEdge = 2732

    // MARK: - Public API

    func cachedThumbnail(_ url: URL) -> UIImage? { memory.object(forKey: key(url, .thumb)) }
    func cachedScreen(_ url: URL) -> UIImage? { screens.object(forKey: key(url, .screen)) }

    func thumbnail(_ url: URL) async -> UIImage? {
        if let img = cachedThumbnail(url) { return img }
        return await Task.detached(priority: .userInitiated) { [self] in loadThumbnail(url) }.value
    }

    func screen(_ url: URL) async -> UIImage? {
        if let img = cachedScreen(url) { return img }
        let edge = screenEdge
        return await Task.detached(priority: .userInitiated) { [self] in
            guard let cg = Self.decode(url, maxEdge: edge) else { return nil }
            let img = UIImage(cgImage: cg)
            screens.setObject(img, forKey: key(url, .screen))
            return img
        }.value
    }

    func full(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            Self.decode(url, maxEdge: 0).map { UIImage(cgImage: $0) }
        }.value
    }

    func preload(_ urls: [URL]) {
        let edge = screenEdge
        for url in urls where cachedScreen(url) == nil {
            Task.detached(priority: .utility) { [self] in
                guard cachedScreen(url) == nil, let cg = Self.decode(url, maxEdge: edge) else { return }
                screens.setObject(UIImage(cgImage: cg), forKey: key(url, .screen))
            }
        }
    }

    /// Thumbnail + pixel analysis, used by the background analysis.
    func analyze(_ url: URL) -> (sharpness: Double, histogram: [Float])? {
        guard let thumb = loadThumbnail(url), let cg = thumb.cgImage else { return nil }
        return PixelBuffers.analyze(cg)
    }

    // MARK: - Disk cache

    var cacheSizeBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func clearCache() {
        memory.removeAllObjects()
        screens.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func clearMemory() {
        memory.removeAllObjects()
        screens.removeAllObjects()
    }

    private func key(_ url: URL, _ level: Level) -> NSString {
        "\(level.rawValue)|\(url.path)" as NSString
    }

    /// Disk cache key: path + size + modification date (a changed file gets a new thumbnail).
    private func diskURL(for url: URL) -> URL? {
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
        let id = "\(url.path)|\(v.fileSize ?? 0)|\(v.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(Self.thumbEdge)"
        let hash = Insecure.MD5.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(hash + ".jpg")
    }

    private func loadThumbnail(_ url: URL) -> UIImage? {
        if let img = cachedThumbnail(url) { return img }
        let disk = diskURL(for: url)
        if let disk, let data = try? Data(contentsOf: disk), let img = UIImage(data: data) {
            memory.setObject(img, forKey: key(url, .thumb))
            return img
        }
        guard let cg = Self.decode(url, maxEdge: Self.thumbEdge) else { return nil }
        let img = UIImage(cgImage: cg)
        memory.setObject(img, forKey: key(url, .thumb))
        if let disk, let data = img.jpegData(compressionQuality: 0.82) {
            try? data.write(to: disk, options: .atomic)
        }
        return img
    }

    // MARK: - Decoding

    /// Decodes an image already rotated by its EXIF orientation.
    /// `maxEdge == 0` means full resolution. For RAW files the embedded JPEG
    /// preview is used when it is big enough (milliseconds instead of seconds).
    static func decode(_ url: URL, maxEdge: Int) -> CGImage? {
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions) else { return nil }
        let raw = FileKinds.isRaw(url.pathExtension)
        var edge = maxEdge
        if edge <= 0 {
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
            let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
            edge = max(w, h, 1)
        }
        func thumb(always: Bool) -> CGImage? {
            var opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: edge,
            ]
            let mode = always ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent
            opts[mode] = true
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        }
        if raw && maxEdge > 0 {
            // embedded preview first; a tiny one (EXIF thumbnail) is not enough
            if let img = thumb(always: false), max(img.width, img.height) >= min(edge, 1000) {
                return img
            }
        }
        return thumb(always: true) ?? (raw ? thumb(always: false) : nil)
    }

    // MARK: - Metadata

    struct Metadata {
        var exif = ExifInfo()
        var pixelWidth = 0
        var pixelHeight = 0
    }

    static func metadata(_ url: URL) -> Metadata {
        var m = Metadata()
        let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, srcOptions) as? [CFString: Any] else { return m }
        var w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        var h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation >= 5 { swap(&w, &h) }
        m.pixelWidth = w
        m.pixelHeight = h

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        var e = ExifInfo()
        e.make = (tiff[kCGImagePropertyTIFFMake] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        e.model = (tiff[kCGImagePropertyTIFFModel] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        e.lens = (exif[kCGImagePropertyExifLensModel] as? String ?? aux[kCGImagePropertyExifAuxLensModel] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        e.exposure = number(exif[kCGImagePropertyExifExposureTime])
        e.fnumber = number(exif[kCGImagePropertyExifFNumber])
        e.focal = number(exif[kCGImagePropertyExifFocalLength])
        if let isos = exif[kCGImagePropertyExifISOSpeedRatings] as? [Any], let first = isos.first {
            e.iso = Int(number(first))
        }
        let dateText = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff[kCGImagePropertyTIFFDateTime] as? String
        if let dateText, var date = exifDateFormatter.date(from: dateText) {
            if let sub = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String,
               let frac = Double("0." + sub.trimmingCharacters(in: .whitespaces)) {
                date.addTimeInterval(frac)
            }
            e.captured = date
        }
        e.width = w
        e.height = h
        m.exif = e
        return m
    }

    private static func number(_ v: Any?) -> Double {
        switch v {
        case let d as Double: return d
        case let n as NSNumber: return n.doubleValue
        case let i as Int: return Double(i)
        case let s as String: return Double(s) ?? 0
        default: return 0
        }
    }

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()
}

/// Renders a CGImage into plain buffers for `ImageAnalysis` (PhotoSelCore).
enum PixelBuffers {
    static func analyze(_ image: CGImage) -> (sharpness: Double, histogram: [Float])? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let rgbaOK = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        var gray = [UInt8](repeating: 0, count: w * h)
        let grayOK = gray.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rgbaOK, grayOK else { return nil }
        return (ImageAnalysis.sharpness(gray: gray, width: w, height: h),
                ImageAnalysis.histogram(rgba: rgba, width: w, height: h))
    }
}

extension UIImage {
    /// View-only rotation (R / Shift+R): 0, 90, 180, 270 degrees clockwise.
    func rotated(_ degrees: Int) -> UIImage {
        guard let cg = cgImage else { return self }
        let o: UIImage.Orientation
        switch ((degrees % 360) + 360) % 360 {
        case 90: o = .right
        case 180: o = .down
        case 270: o = .left
        default: return self
        }
        return UIImage(cgImage: cg, scale: scale, orientation: o)
    }
}
