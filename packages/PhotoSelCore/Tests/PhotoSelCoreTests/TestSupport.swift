import Foundation
@testable import PhotoSelCore

let folder = URL(fileURLWithPath: "/photos/100MSDCF", isDirectory: true)
let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func entry(_ name: String, size: Int64 = 100, at seconds: Double = 0) -> FileEntry {
    FileEntry(url: folder.appendingPathComponent(name), size: size, modified: t0.addingTimeInterval(seconds))
}

/// Photos named P0, P1... taken at the given offsets in seconds.
func makePhotos(_ times: [Double], gapMs: Int = 1000) -> [Photo] {
    let raw = times.enumerated().map { i, t -> Photo in
        var p = Photo(baseName: "P\(i)", folder: folder)
        p.files["jpg"] = folder.appendingPathComponent("P\(i).JPG")
        p.displayExt = "jpg"
        p.sortTime = t0.addingTimeInterval(t)
        return p
    }
    return PhotoGrouper.finalize(raw, burstGapMs: gapMs)
}

func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("photosel-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
