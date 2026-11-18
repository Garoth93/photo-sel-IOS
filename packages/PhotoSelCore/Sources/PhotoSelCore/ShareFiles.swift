import Foundation

/// Which file of each photo is sent to another app (Lightroom, Files, AirDrop…).
public enum ShareFormat: String, Codable, CaseIterable, Sendable {
    /// The RAW when there is one, otherwise the shown file. Default: Lightroom works best on RAW.
    case raw
    /// The JPG/HEIC when there is one, otherwise the RAW.
    case jpeg
    /// Every image file of the photo (no XMP): JPG and RAW become two photos in Lightroom.
    case both

    public var title: String {
        switch self {
        case .raw: return "RAW (se c'è)"
        case .jpeg: return "JPG (se c'è)"
        case .both: return "Tutti i file"
        }
    }
}

public enum ShareFiles {
    public static func urls(for photo: Photo, format: ShareFormat) -> [URL] {
        let images = FileKinds.sorted(photo.files.keys.filter { $0 != FileKinds.sidecar })
        let raw = images.first { FileKinds.isRaw($0) }
        let nonRaw = images.first { !FileKinds.isRaw($0) }
        let exts: [String]
        switch format {
        case .raw: exts = [raw ?? (photo.displayExt.isEmpty ? nonRaw : photo.displayExt)].compactMap { $0 }
        case .jpeg: exts = [nonRaw ?? raw].compactMap { $0 }
        case .both: exts = images
        }
        return exts.compactMap { photo.files[$0] }
    }

    /// Files of many photos, in the given order, without duplicates.
    public static func urls(for photos: [Photo], format: ShareFormat) -> [URL] {
        var seen = Set<String>()
        return photos.flatMap { urls(for: $0, format: format) }.filter { seen.insert($0.path).inserted }
    }
}

/// Multi-selection in the grid, by uid. Uids change when the folder is read
/// again, so the app clears the selection on every scan.
public struct PhotoSelection: Equatable, Sendable {
    public private(set) var uids: Set<Int> = []

    public init() {}

    public var count: Int { uids.count }
    public var isEmpty: Bool { uids.isEmpty }
    public func contains(_ uid: Int) -> Bool { uids.contains(uid) }

    public mutating func toggle(_ uid: Int) {
        if uids.contains(uid) { uids.remove(uid) } else { uids.insert(uid) }
    }

    public mutating func set(_ newUIDs: [Int]) { uids = Set(newUIDs) }
    public mutating func add(_ more: [Int]) { uids.formUnion(more) }
    public mutating func clear() { uids.removeAll() }

    /// Selected photos in the session's chronological order.
    public func photos(in session: CullSession) -> [Photo] {
        session.photos.filter { uids.contains($0.uid) }
    }
}
