import XCTest
@testable import PhotoSelCore

final class ShareFilesTests: XCTestCase {
    private func photo(_ name: String, _ exts: [String], uid: Int = 0) -> Photo {
        var p = Photo(baseName: name, folder: folder)
        for e in exts { p.files[e] = folder.appendingPathComponent("\(name).\(e.uppercased())") }
        p.displayExt = exts.first { $0 != "xmp" } ?? ""
        p.uid = uid
        return p
    }

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    func testFormats() {
        let both = photo("A", ["jpg", "arw", "xmp"])
        XCTAssertEqual(names(ShareFiles.urls(for: both, format: .raw)), ["A.ARW"])
        XCTAssertEqual(names(ShareFiles.urls(for: both, format: .jpeg)), ["A.JPG"])
        XCTAssertEqual(names(ShareFiles.urls(for: both, format: .both)), ["A.JPG", "A.ARW"])   // never the XMP

        let jpgOnly = photo("B", ["jpg"])
        XCTAssertEqual(names(ShareFiles.urls(for: jpgOnly, format: .raw)), ["B.JPG"])
        let rawOnly = photo("C", ["nef"])
        XCTAssertEqual(names(ShareFiles.urls(for: rawOnly, format: .jpeg)), ["C.NEF"])
        let heic = photo("D", ["heic", "dng"])
        XCTAssertEqual(names(ShareFiles.urls(for: heic, format: .jpeg)), ["D.HEIC"])
    }

    func testManyPhotosKeepOrderWithoutDuplicates() {
        let a = photo("A", ["jpg", "arw"]), b = photo("B", ["jpg"])
        XCTAssertEqual(names(ShareFiles.urls(for: [b, a, b], format: .raw)), ["B.JPG", "A.ARW"])
    }

    func testSelection() {
        let s = CullSession(photos: makePhotos([0, 10, 20, 30]))
        var sel = PhotoSelection()
        sel.toggle(2); sel.toggle(0); sel.toggle(3); sel.toggle(3)
        XCTAssertEqual(sel.count, 2)
        XCTAssertTrue(sel.contains(0))
        XCTAssertEqual(sel.photos(in: s).map(\.uid), [0, 2])     // chronological order
        sel.add([1, 2])
        XCTAssertEqual(sel.count, 3)
        sel.set([3])
        XCTAssertEqual(sel.photos(in: s).map(\.baseName), ["P3"])
        sel.clear()
        XCTAssertTrue(sel.isEmpty)
    }

    func testShareFormatSetting() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"shareFormat": "both"}"#.utf8))
        XCTAssertEqual(s.shareFormat, .both)
        let d = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"shareFormat": 3}"#.utf8))
        XCTAssertEqual(d.shareFormat, .raw)
    }
}
