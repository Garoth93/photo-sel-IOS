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
        ], folder: folder, preferRaw: false)

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
        let photos = PhotoGrouper.group([entry("A.JPG"), entry("A.NEF")], folder: folder, preferRaw: true)
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
                                        folder: folder, preferRaw: false)
        XCTAssertEqual(PhotoGrouper.extensions(of: photos), ["jpg", "png", "arw", "xmp"])
    }
}
