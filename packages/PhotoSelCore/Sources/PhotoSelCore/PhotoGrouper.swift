import Foundation

/// A file found in the folder (the app lists the folder, the package groups).
public struct FileEntry: Equatable, Sendable {
    public var url: URL
    public var size: Int64
    public var modified: Date

    public init(url: URL, size: Int64, modified: Date) {
        self.url = url
        self.size = size
        self.modified = modified
    }

    public var ext: String { url.pathExtension.lowercased() }
    /// "DSC01234.JPG" -> "DSC01234" (like Qt's completeBaseName).
    public var baseName: String { url.deletingPathExtension().lastPathComponent }
}

/// Port of `scanFolder` of the Qt app, without the I/O: grouping by base name,
/// choice of the displayed file, chronological order and bursts.
public enum PhotoGrouper {
    /// Groups the files by base name (case-insensitive). XMP sidecars without a photo
    /// are ignored. `sortTime` is set to the modification date of the shown file:
    /// the app replaces it with the capture time when EXIF has one.
    public static func group(_ entries: [FileEntry], folder: URL, preferRaw: Bool) -> [Photo] {
        let sortedEntries = entries.sorted {
            $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
        }
        var byBase: [String: Int] = [:]
        var photos: [Photo] = []
        var modified: [Int: [String: Date]] = [:]

        for e in sortedEntries where e.ext != FileKinds.sidecar && FileKinds.isSupported(e.ext) {
            let key = e.baseName.lowercased()
            let idx: Int
            if let i = byBase[key] {
                idx = i
            } else {
                idx = photos.count
                byBase[key] = idx
                photos.append(Photo(baseName: e.baseName, folder: folder))
            }
            guard photos[idx].files[e.ext] == nil else { continue }
            photos[idx].files[e.ext] = e.url
            photos[idx].totalBytes += e.size
            modified[idx, default: [:]][e.ext] = e.modified
        }
        for e in sortedEntries where e.ext == FileKinds.sidecar {
            guard let idx = byBase[e.baseName.lowercased()], photos[idx].files[FileKinds.sidecar] == nil else { continue }
            photos[idx].files[FileKinds.sidecar] = e.url
            photos[idx].totalBytes += e.size
        }

        for i in photos.indices {
            let best = photos[i].files.keys
                .filter { $0 != FileKinds.sidecar }
                .min { a, b in
                    let ra = FileKinds.displayRank(a, preferRaw: preferRaw)
                    let rb = FileKinds.displayRank(b, preferRaw: preferRaw)
                    return ra != rb ? ra < rb : a < b
                } ?? ""
            photos[i].displayExt = best
            photos[i].sortTime = modified[i]?[best] ?? .distantPast
        }
        return photos
    }

    /// Chronological order (name as tie-break), uid = position, bursts = shots
    /// closer than `burstGapMs` to the previous one (at least 2 photos).
    public static func finalize(_ input: [Photo], burstGapMs: Int) -> [Photo] {
        var photos = input.enumerated().sorted { a, b in
            if a.element.sortTime != b.element.sortTime { return a.element.sortTime < b.element.sortTime }
            let c = a.element.baseName.localizedCaseInsensitiveCompare(b.element.baseName)
            if c != .orderedSame { return c == .orderedAscending }
            return a.offset < b.offset   // stable
        }.map(\.element)

        for i in photos.indices {
            photos[i].uid = i
            photos[i].burstId = -1
            photos[i].burstIndex = 0
            photos[i].burstSize = 1
        }
        let gap = Double(max(0, burstGapMs)) / 1000
        var burstId = 0
        var start = 0
        if photos.isEmpty { return photos }
        for i in 1...photos.count {
            let breaks = i == photos.count
                || photos[i].sortTime.timeIntervalSince(photos[i - 1].sortTime) > gap + 1e-9
            guard breaks else { continue }
            let size = i - start
            if size >= 2 {
                for k in start..<i {
                    photos[k].burstId = burstId
                    photos[k].burstIndex = k - start
                    photos[k].burstSize = size
                }
                burstId += 1
            }
            start = i
        }
        return photos
    }

    /// Extensions present in the folder, in display order.
    public static func extensions(of photos: [Photo]) -> [String] {
        FileKinds.sorted(photos.flatMap { $0.files.keys })
    }
}
