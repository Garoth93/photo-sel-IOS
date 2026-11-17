import Foundation

public enum ExportSelection: String, Codable, CaseIterable, Sendable {
    case picks, stars, notRejected, all

    public func includes(_ p: Photo, minStars: Int) -> Bool {
        switch self {
        case .picks: return p.flag == 1
        case .stars: return p.flag != -1 && p.stars >= minStars
        case .notRejected: return p.flag != -1
        case .all: return true
        }
    }
}

/// Options of the export sheet, remembered between sessions.
public struct ExportOptions: Codable, Equatable, Sendable {
    public var selection: ExportSelection = .picks
    public var minStars = 1
    public var formats: [String] = []
    /// Destination inside the opened folder, used when no other folder is chosen.
    public var subfolder = "selezionate"
    public var perFormatFolder = true
    public var move = false
    public var moveRejects = false
    public var rejectFolder = "da_eliminare"
    /// iPad only: also add the exported photos to the Photos library.
    public var saveToPhotos = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExportOptions()
        selection = (try? c.decodeIfPresent(ExportSelection.self, forKey: .selection)) ?? d.selection
        minStars = min(max((try? c.decodeIfPresent(Int.self, forKey: .minStars)) ?? d.minStars, 1), 5)
        formats = (try? c.decodeIfPresent([String].self, forKey: .formats)) ?? d.formats
        subfolder = (try? c.decodeIfPresent(String.self, forKey: .subfolder)) ?? d.subfolder
        perFormatFolder = (try? c.decodeIfPresent(Bool.self, forKey: .perFormatFolder)) ?? d.perFormatFolder
        move = (try? c.decodeIfPresent(Bool.self, forKey: .move)) ?? d.move
        moveRejects = (try? c.decodeIfPresent(Bool.self, forKey: .moveRejects)) ?? d.moveRejects
        rejectFolder = (try? c.decodeIfPresent(String.self, forKey: .rejectFolder)) ?? d.rejectFolder
        saveToPhotos = (try? c.decodeIfPresent(Bool.self, forKey: .saveToPhotos)) ?? d.saveToPhotos
    }

    /// Keeps only the formats present in this folder; default: the RAW files
    /// (as in version 1), otherwise the first format.
    public func validFormats(available: [String]) -> [String] {
        var valid = formats.filter { available.contains($0) }
        if valid.isEmpty {
            valid = available.filter { FileKinds.isRaw($0) }
            if valid.isEmpty, let first = available.first { valid = [first] }
        }
        return valid
    }

    /// Cleans a folder name typed by the user ("" -> fallback, no slashes).
    public static func cleanFolderName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return trimmed.isEmpty || trimmed == "." || trimmed == ".." ? fallback : trimmed
    }
}

public struct ExportItem: Equatable, Sendable {
    public var source: URL
    /// Subfolder relative to the destination ("" = root).
    public var subdir: String

    public init(source: URL, subdir: String) {
        self.source = source
        self.subdir = subdir
    }
}

public struct ExportPlan: Equatable, Sendable {
    public var destination: URL
    public var move = false
    /// One list of files per photo.
    public var photos: [[ExportItem]] = []
    public var rejectDir: URL?
    public var rejects: [[URL]] = []

    public var totalFiles: Int {
        photos.reduce(0) { $0 + $1.count } + rejects.reduce(0) { $0 + $1.count }
    }
    public var isEmpty: Bool { photos.isEmpty && rejects.isEmpty }
}

public enum ExportPlanError: Error, Equatable {
    case sameFolder
    case nothingSelected

    public var message: String {
        switch self {
        case .sameFolder: return "Scegli una destinazione diversa dalla cartella delle foto"
        case .nothingSelected: return "Nessuna foto corrisponde alla selezione con i formati scelti"
        }
    }
}

public enum ExportPlanner {
    public static func count(_ photos: [Photo], selection: ExportSelection, minStars: Int) -> Int {
        photos.filter { selection.includes($0, minStars: minStars) }.count
    }

    /// Port of `AppController::startExport` (plan part).
    public static func plan(photos: [Photo], options o: ExportOptions, folder: URL, destination: URL) -> Result<ExportPlan, ExportPlanError> {
        var plan = ExportPlan(destination: destination, move: o.move)
        let formats = o.formats
        if !formats.isEmpty {
            if !o.perFormatFolder && sameDirectory(destination, folder) { return .failure(.sameFolder) }
            for p in photos where o.selection.includes(p, minStars: o.minStars) {
                var items: [ExportItem] = []
                var xmpFolder: String?
                for f in formats where f != FileKinds.sidecar {
                    guard let url = p.files[f] else { continue }
                    let sub = o.perFormatFolder ? f : ""
                    items.append(ExportItem(source: url, subdir: sub))
                    // the sidecar goes next to the RAW (where Lightroom looks for it)
                    if xmpFolder == nil || FileKinds.isRaw(f) { xmpFolder = sub }
                }
                if formats.contains(FileKinds.sidecar), let xmp = p.files[FileKinds.sidecar], !items.isEmpty {
                    items.append(ExportItem(source: xmp, subdir: xmpFolder ?? ""))
                }
                if !items.isEmpty { plan.photos.append(items) }
            }
        }
        if o.moveRejects {
            let name = ExportOptions.cleanFolderName(o.rejectFolder, fallback: "da_eliminare")
            plan.rejectDir = folder.appendingPathComponent(name, isDirectory: true)
            for p in photos where p.flag == -1 {
                let files = p.files.keys.sorted().compactMap { p.files[$0] }
                plan.rejects.append(files)
            }
        }
        return plan.isEmpty ? .failure(.nothingSelected) : .success(plan)
    }

    static func sameDirectory(_ a: URL, _ b: URL) -> Bool {
        a.standardizedFileURL.resolvingSymlinksInPath().path.trimmingSuffix("/")
            == b.standardizedFileURL.resolvingSymlinksInPath().path.trimmingSuffix("/")
    }

    /// Finds a free " (n)" suffix for ALL the files of a photo, so JPG, RAW and
    /// XMP stay paired even when names clash.
    public static func freeSuffix(_ targets: [(dir: URL, fileName: String)], exists: (URL) -> Bool) -> String {
        for n in 0..<10000 {
            let suffix = n == 0 ? "" : " (\(n))"
            let free = targets.allSatisfy { t in
                !exists(t.dir.appendingPathComponent(suffixed(t.fileName, suffix)))
            }
            if free { return suffix }
        }
        return " (dup)"
    }

    /// "DSC1.ARW" + " (2)" -> "DSC1 (2).ARW"
    public static func suffixed(_ fileName: String, _ suffix: String) -> String {
        guard !suffix.isEmpty else { return fileName }
        let url = URL(fileURLWithPath: fileName)
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        return ext.isEmpty ? base + suffix : base + suffix + "." + ext
    }
}

public struct ExportProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int
    public var fileName: String

    public init(done: Int, total: Int, fileName: String) {
        self.done = done
        self.total = total
        self.fileName = fileName
    }
}

public struct ExportResult: Equatable, Sendable {
    public var photos = 0
    public var files = 0
    public var failed = 0
    public var cancelled = false
    public var firstError = ""
    /// Files written in the destination, per photo (used to add them to Photos).
    public var exported: [[URL]] = []

    public init() {}

    public var ok: Bool { failed == 0 && !cancelled }

    public var message: String {
        let done = photos == 1 ? "1 foto esportata" : "\(photos) foto esportate"
        let nfiles = files == 1 ? "1 file" : "\(files) file"
        if cancelled { return "Esportazione interrotta: \(done)" }
        if failed > 0 { return "\(done), \(failed) file non riusciti. \(firstError)" }
        if photos == 0 && files == 0 { return "Scartate spostate" }
        return "\(done) (\(nfiles))"
    }
}

/// Copies or moves the files of a plan. Synchronous: the app runs it off the
/// main thread. Works with any FileManager-reachable URL (also on Linux).
public enum ExportRunner {
    public static func run(_ plan: ExportPlan,
                           fileManager fm: FileManager = .default,
                           isCancelled: () -> Bool = { false },
                           progress: (ExportProgress) -> Void = { _ in }) -> ExportResult {
        var r = ExportResult()
        let total = plan.totalFiles
        var done = 0

        if !plan.photos.isEmpty {
            do {
                try fm.createDirectory(at: plan.destination, withIntermediateDirectories: true)
            } catch {
                r.firstError = "La cartella di destinazione non è scrivibile"
                r.failed = total
                return r
            }
        }
        for photo in plan.photos {
            if isCancelled() { break }
            let targets: [(dir: URL, fileName: String)] = photo.map { item in
                let dir = item.subdir.isEmpty ? plan.destination
                    : plan.destination.appendingPathComponent(item.subdir, isDirectory: true)
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                return (dir, item.source.lastPathComponent)
            }
            let suffix = ExportPlanner.freeSuffix(targets) { fm.fileExists(atPath: $0.path) }
            var written: [URL] = []
            for (i, item) in photo.enumerated() {
                let dst = targets[i].dir.appendingPathComponent(ExportPlanner.suffixed(targets[i].fileName, suffix))
                progress(ExportProgress(done: done, total: total, fileName: item.source.lastPathComponent))
                if let err = transfer(item.source, to: dst, move: plan.move, fm: fm) {
                    r.failed += 1
                    if r.firstError.isEmpty { r.firstError = err }
                } else {
                    r.files += 1
                    written.append(dst)
                }
                done += 1
            }
            if !written.isEmpty {
                r.photos += 1
                r.exported.append(written)
            }
        }
        if !isCancelled(), let rejectDir = plan.rejectDir, !plan.rejects.isEmpty {
            try? fm.createDirectory(at: rejectDir, withIntermediateDirectories: true)
            for reject in plan.rejects {
                if isCancelled() { break }
                let targets = reject.map { (dir: rejectDir, fileName: $0.lastPathComponent) }
                let suffix = ExportPlanner.freeSuffix(targets) { fm.fileExists(atPath: $0.path) }
                for f in reject {
                    let dst = rejectDir.appendingPathComponent(ExportPlanner.suffixed(f.lastPathComponent, suffix))
                    progress(ExportProgress(done: done, total: total, fileName: f.lastPathComponent))
                    if let err = transfer(f, to: dst, move: true, fm: fm) {
                        r.failed += 1
                        if r.firstError.isEmpty { r.firstError = err }
                    }
                    done += 1
                }
            }
        }
        r.cancelled = isCancelled()
        progress(ExportProgress(done: done, total: total, fileName: ""))
        return r
    }

    /// Returns an error message, or nil on success.
    static func transfer(_ src: URL, to dst: URL, move: Bool, fm: FileManager) -> String? {
        if move {
            do {
                try fm.moveItem(at: src, to: dst)
                return nil
            } catch {
                return "Impossibile spostare \(src.lastPathComponent)"
            }
        }
        do {
            try fm.copyItem(at: src, to: dst)
        } catch {
            return "Impossibile copiare \(src.lastPathComponent)"
        }
        // keep the original date (useful for whoever sorts by date)
        if let date = (try? fm.attributesOfItem(atPath: src.path))?[.modificationDate] as? Date {
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: dst.path)
        }
        return nil
    }
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        var s = self
        while s.count > 1 && s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        return s
    }
}
