import XCTest
@testable import PhotoSelCore

final class PhotoGrouperTests: XCTestCase {
    func testGroupsJpgRawAndXmp() {
        let photos = PhotoGrouper.group([
            entry("DSC0002.ARW", size: 25, at: 10),
            entry("DSC0001.JPG", size: 5, at: 1),
            entry("DSC0001.ARW", size: 20, at: 2),
            entry("dsc0001.xmp", size: 1),
            entry("DSC0003.xmp"),          // sidecar without photo: ignored
            entry("notes.txt"),            // unsupported: ignored
            entry("DSC0002.JPG", size: 6, at: 11),
        ], preferRaw: false)

        XCTAssertEqual(photos.map(\.baseName), ["DSC0001", "DSC0002"])
        let p = photos[0]
        XCTAssertEqual(Set(p.files.keys), ["jpg", "arw", "xmp"])
        XCTAssertEqual(p.totalBytes, 26)
        XCTAssertEqual(p.displayExt, "jpg")
        XCTAssertEqual(p.sortTime, t0.addingTimeInterval(1))
        XCTAssertEqual(p.extensionBadges, ["JPG", "ARW", "XMP"])
        XCTAssertTrue(p.hasRaw)
        XCTAssertEqual(p.xmpURL.lastPathComponent, "dsc0001.xmp")
        XCTAssertEqual(photos[1].xmpURL.lastPathComponent, "DSC0002.xmp")
    }

    func testPreferRaw() {
        let photos = PhotoGrouper.group([entry("A.JPG"), entry("A.NEF")], preferRaw: true)
        XCTAssertEqual(photos[0].displayExt, "nef")
        XCTAssertEqual(photos[0].extensionBadges, ["NEF", "JPG"])
    }

    func testFinalizeOrdersAndFindsBursts() {
        // 0, 0.4, 0.9 -> burst of 3; 5 alone; 10, 10.5 -> burst of 2
        let photos = makePhotos([10.5, 0, 5, 0.9, 10, 0.4].map { $0 })
        XCTAssertEqual(photos.map(\.uid), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(photos.map(\.baseName), ["P1", "P5", "P3", "P2", "P4", "P0"])
        XCTAssertEqual(photos.map(\.burstSize), [3, 3, 3, 1, 2, 2])
        XCTAssertEqual(photos.map(\.burstIndex), [0, 1, 2, 0, 0, 1])
        XCTAssertEqual(photos.map(\.burstId), [0, 0, 0, -1, 1, 1])
    }

    func testBurstGapBoundaryAndNameTieBreak() {
        let photos = makePhotos([0, 1, 2.5], gapMs: 1000)
        XCTAssertEqual(photos.map(\.burstSize), [2, 2, 1])
        var a = Photo(baseName: "b", folder: folder); a.sortTime = t0
        var b = Photo(baseName: "A", folder: folder); b.sortTime = t0
        XCTAssertEqual(PhotoGrouper.finalize([a, b], burstGapMs: 0).map(\.baseName), ["A", "b"])
        XCTAssertTrue(PhotoGrouper.finalize([], burstGapMs: 1000).isEmpty)
    }

    func testExtensions() {
        let photos = PhotoGrouper.group([entry("A.JPG"), entry("A.ARW"), entry("A.xmp"), entry("B.png")],
                                        preferRaw: false)
        XCTAssertEqual(PhotoGrouper.extensions(of: photos), ["jpg", "png", "arw", "xmp"])
    }

    // MARK: - Files of one shot in different folders

    private func at(_ path: String, _ seconds: Double, size: Int64 = 10) -> FileEntry {
        FileEntry(url: card.appendingPathComponent(path), size: size, modified: t0.addingTimeInterval(seconds))
    }

    func testPairsJpgAndRawInSeparateFolders() {
        let photos = PhotoGrouper.group([
            at("DCIM/100MSDCF/DSC0001.JPG", 0),
            at("DCIM/100MSDCF/DSC0002.JPG", 5),
            at("RAW/DSC0001.ARW", 1),
            at("RAW/DSC0002.ARW", 6),
            at("RAW/DSC0001.xmp", 100),
        ], preferRaw: false)
        XCTAssertEqual(photos.count, 2)
        let p = photos.first { $0.baseName == "DSC0001" }!
        XCTAssertEqual(Set(p.files.keys), ["jpg", "arw", "xmp"])
        XCTAssertEqual(p.displayExt, "jpg")
        XCTAssertEqual(p.folder.lastPathComponent, "RAW")            // sidecars next to the RAW
        XCTAssertEqual(p.xmpURL.path, card.appendingPathComponent("RAW/DSC0001.xmp").path)
        XCTAssertEqual(p.directories.count, 2)
        let q = photos.first { $0.baseName == "DSC0002" }!
        XCTAssertEqual(q.xmpURL.path, card.appendingPathComponent("RAW/DSC0002.xmp").path)
        XCTAssertNil(q.files["xmp"])
    }

    func testCounterWrapKeepsDifferentShotsApart() {
        // same names in two folders, hours apart: four different files -> three shots
        let photos = PhotoGrouper.group([
            at("DCIM/100MSDCF/DSC0001.JPG", 0),
            at("DCIM/100MSDCF/DSC0001.ARW", 1),
            at("DCIM/105MSDCF/DSC0001.JPG", 20_000),
            at("DCIM/106MSDCF/DSC0001.ARW", 50_000),
        ], preferRaw: false)
        XCTAssertEqual(photos.count, 3)
        XCTAssertEqual(photos.map { $0.files.count }.sorted(), [1, 1, 2])
    }

    func testSplitFoldersWithWrapUseCaptureTime() {
        // modification dates are useless here (files copied later): EXIF decides
        let exif: [String: Double] = [
            "JPG/100/DSC0001.JPG": 0, "JPG/101/DSC0001.JPG": 9000,
            "RAW/100/DSC0001.ARW": 1, "RAW/101/DSC0001.ARW": 9001,
        ]
        let entries = exif.keys.map { at($0, 500) }
        let photos = PhotoGrouper.group(entries, preferRaw: false) { url in
            let rel = PhotoGrouper.relativePath(of: url, to: card)
            return exif[rel].map { t0.addingTimeInterval($0) }
        }
        XCTAssertEqual(photos.count, 2)
        for p in photos {
            let jpgDir = p.files["jpg"]!.deletingLastPathComponent().lastPathComponent
            let rawDir = p.files["arw"]!.deletingLastPathComponent().lastPathComponent
            XCTAssertEqual(jpgDir, rawDir)
        }
    }

    func testSidecarGoesToPhotoInSameFolder() {
        let photos = PhotoGrouper.group([
            at("A/DSC0001.JPG", 0), at("A/DSC0001.xmp", 0),
            at("B/DSC0001.JPG", 90_000),
        ], preferRaw: false)
        XCTAssertEqual(photos.count, 2)
        let a = photos.first { $0.folder.lastPathComponent == "A" }!
        let b = photos.first { $0.folder.lastPathComponent == "B" }!
        XCTAssertNotNil(a.files["xmp"])
        XCTAssertNil(b.files["xmp"])
    }

    func testIdentityAndRelativePath() {
        let photos = PhotoGrouper.group([at("J/X.JPG", 0), at("R/X.ARW", 0)], preferRaw: false)
        let raw = PhotoGrouper.group([at("J/X.JPG", 0), at("R/X.ARW", 0)], preferRaw: true)
        XCTAssertEqual(photos[0].identity, raw[0].identity)       // stable when the shown file changes
        XCTAssertEqual(PhotoGrouper.relativePath(of: card.appendingPathComponent("DCIM/100"), to: card), "DCIM/100")
        XCTAssertEqual(PhotoGrouper.relativePath(of: card, to: card), "")
        XCTAssertEqual(PhotoGrouper.relativePath(of: URL(fileURLWithPath: "/other/x"), to: card), "x")
    }
}
