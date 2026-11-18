import Foundation

/// A file found under the opened folder (the scanner lists, the grouper groups).
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
    public var directory: URL { url.deletingLastPathComponent() }
}

/// Port of `scanFolder` of the Qt app, without the I/O: grouping by base name,
/// choice of the displayed file, chronological order and bursts.
///
/// Unlike the desktop version the files of one shot may live in different
/// folders (e.g. `DCIM/100MSDCF/DSC0001.JPG` and `RAW/DSC0001.ARW`, or a camera
/// that writes JPG and RAW in separate folders). Files with the same base name:
/// - in the same folder are always the same shot (a camera never reuses a name
///   inside a folder);
/// - in different folders are the same shot only if their capture times are
///   close: when the counter wraps (DSC09999 -> DSC00001 in a new folder) the
///   same name belongs to different shots.
public enum PhotoGrouper {
    /// Max distance between capture times of files of the same shot in different folders.
    public static let pairingTolerance: TimeInterval = 120

    /// Groups the files into photos. `captureTime` is asked only for files whose
    /// base name appears in more than one folder (EXIF date; the modification
    /// date is used when it returns nil). `sortTime` is set to the modification
    /// date of the shown file: the app replaces it with the EXIF capture time.
    public static func group(_ entries: [FileEntry], preferRaw: Bool,
                             captureTime: (URL) -> Date? = { _ in nil }) -> [Photo] {
        let sortedEntries = entries.sorted {
            $0.url.path.compare($1.url.path, options: [.caseInsensitive, .numeric]) == .orderedAscending
        }
        var order: [String] = []
        var buckets: [String: [FileEntry]] = [:]
        var sidecars: [FileEntry] = []
        for e in sortedEntries {
            if e.ext == FileKinds.sidecar { sidecars.append(e); continue }
            guard FileKinds.isSupported(e.ext) else { continue }
            let key = e.baseName.lowercased()
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(e)
        }

        var photos: [Photo] = []
        var photosByKey: [String: [Int]] = [:]
        for key in order {
            for cluster in clusters(buckets[key] ?? [], captureTime: captureTime) {
                photosByKey[key, default: []].append(photos.count)
                photos.append(makePhoto(cluster, preferRaw: preferRaw))
            }
        }

        // XMP sidecars: the photo with a file in the same folder (the RAW first,
        // where Lightroom puts it); with a single candidate, that one.
        for x in sidecars {
            guard let candidates = photosByKey[x.baseName.lowercased()] else { continue }
            let dir = normalized(x.directory)
            let inSameDir = candidates.filter { i in
                photos[i].files.values.contains { normalized($0.deletingLastPathComponent()) == dir }
            }
            let withRaw = inSameDir.filter { i in photos[i].rawURL.map { normalized($0.deletingLastPathComponent()) == dir } ?? false }
            let target = withRaw.first ?? inSameDir.first ?? (candidates.count == 1 ? candidates[0] : nil)
            guard let t = target, photos[t].files[FileKinds.sidecar] == nil else { continue }
            photos[t].files[FileKinds.sidecar] = x.url
            photos[t].totalBytes += x.size
        }
        return photos
    }

    /// Splits the files with one base name into shots.
    static func clusters(_ files: [FileEntry], captureTime: (URL) -> Date?) -> [[FileEntry]] {
        // same folder = same shot (one file per extension)
        var unitOrder: [String] = []
        var units: [String: [FileEntry]] = [:]
        for f in files {
            let dir = normalized(f.directory)
            if units[dir] == nil { unitOrder.append(dir) }
            if units[dir]?.contains(where: { $0.ext == f.ext }) == true { continue }
            units[dir, default: []].append(f)
        }
        if unitOrder.count <= 1 { return unitOrder.compactMap { units[$0] } }

        struct Cluster { var files: [FileEntry]; var time: Date; var exts: Set<String> }
        let timed: [(files: [FileEntry], time: Date)] = unitOrder.compactMap { dir in
            guard let u = units[dir] else { return nil }
            let t = u.map { captureTime($0.url) ?? $0.modified }.min() ?? .distantPast
            return (u, t)
        }.sorted { $0.time < $1.time }

        var result: [Cluster] = []
        for unit in timed {
            let exts = Set(unit.files.map(\.ext))
            var best: Int?
            var bestDistance = TimeInterval.infinity
            for (i, c) in result.enumerated() where c.exts.isDisjoint(with: exts) {
                let d = abs(c.time.timeIntervalSince(unit.time))
                if d <= pairingTolerance && d < bestDistance {
                    best = i
                    bestDistance = d
                }
            }
            if let b = best {
                result[b].files += unit.files
                result[b].exts.formUnion(exts)
            } else {
                result.append(Cluster(files: unit.files, time: unit.time, exts: exts))
            }
        }
        return result.map(\.files)
    }

    static func makePhoto(_ files: [FileEntry], preferRaw: Bool) -> Photo {
        let display = files.min { a, b in
            let ra = FileKinds.displayRank(a.ext, preferRaw: preferRaw)
            let rb = FileKinds.displayRank(b.ext, preferRaw: preferRaw)
            return ra != rb ? ra < rb : a.ext < b.ext
        } ?? files[0]
        // new sidecars go next to the RAW, where Lightroom looks for them
        let anchor = files.first { FileKinds.isRaw($0.ext) } ?? display
        var p = Photo(baseName: anchor.baseName, folder: anchor.directory)
        for f in files {
            p.files[f.ext] = f.url
            p.totalBytes += f.size
        }
        p.displayExt = display.ext
        p.sortTime = display.modified
        return p
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

    /// "/card/DCIM/100MSDCF" relative to "/card" -> "DCIM/100MSDCF"; the root itself -> "".
    public static func relativePath(of dir: URL, to root: URL) -> String {
        let d = normalized(dir), r = normalized(root)
        if d == r { return "" }
        if d.hasPrefix(r + "/") { return String(d.dropFirst(r.count + 1)) }
        return dir.lastPathComponent
    }

    static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.path.trimmingSuffix("/")
    }
}

/// Recursive listing of the opened folder (SD card root, DCIM, any folder).
public enum FolderScanner {
    public static let maxDepth = 6

    /// Image and XMP files under `root`, also in subfolders up to `maxDepth`.
    /// Hidden entries and the `excluded` folders (e.g. the export destination,
    /// the rejects folder) are skipped. Throws only if `root` cannot be read.
    public static func listFiles(in root: URL, excluding excluded: [URL] = [],
                                 maxDepth: Int = maxDepth,
                                 fileManager fm: FileManager = .default) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let skip = Set(excluded.map(PhotoGrouper.normalized))
        var out: [FileEntry] = []
        var stack: [(URL, Int)] = [(root, 0)]
        while let item = stack.popLast() {
            let (dir, depth) = item
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            } catch {
                if depth == 0 { throw error }
                continue
            }
            for url in items where !url.lastPathComponent.hasPrefix(".") {
                let v = try? url.resourceValues(forKeys: Set(keys))
                if v?.isDirectory == true {
                    if depth < maxDepth && !skip.contains(PhotoGrouper.normalized(url)) {
                        stack.append((url, depth + 1))
                    }
                    continue
                }
                guard v?.isRegularFile ?? true else { continue }
                let ext = url.pathExtension.lowercased()
                guard ext == FileKinds.sidecar || FileKinds.isSupported(ext) else { continue }
                out.append(FileEntry(url: url, size: Int64(v?.fileSize ?? 0),
                                     modified: v?.contentModificationDate ?? .distantPast))
            }
        }
        return out
    }
}
