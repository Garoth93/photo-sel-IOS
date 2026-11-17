import XCTest
@testable import PhotoSelCore

final class FormatTests: XCTestCase {
    func testExposure() {
        var e = ExifInfo()
        XCTAssertEqual(e.exposureText, "")
        e.exposure = 1.0 / 500
        XCTAssertEqual(e.exposureText, "1/500")
        e.exposure = 1.0 / 3
        XCTAssertEqual(e.exposureText, "1/3")
        e.exposure = 2.5
        XCTAssertEqual(e.exposureText, "2,5″")
        e.exposure = 30
        XCTAssertEqual(e.exposureText, "30″")
    }

    func testApertureFocalIso() {
        var e = ExifInfo()
        e.fnumber = 2.8
        e.focal = 35.4
        e.iso = 400
        XCTAssertEqual(e.apertureText, "f/2.8")
        XCTAssertEqual(e.focalText, "35 mm")
        XCTAssertEqual(e.isoText, "ISO 400")
        e.fnumber = 11
        XCTAssertEqual(e.apertureText, "f/11")
        e.fnumber = 0.95
        XCTAssertEqual(e.apertureText, "f/0.95")
        e.exposure = 1.0 / 1000
        XCTAssertEqual(e.summaryLine, "1/1000   f/0.95   ISO 400   35 mm")
    }

    func testCameraText() {
        var e = ExifInfo()
        e.make = "SONY"
        e.model = "ILCE-6700"
        XCTAssertEqual(e.cameraText, "Sony ILCE-6700")
        e.make = "Canon"
        e.model = "Canon EOS R6"
        XCTAssertEqual(e.cameraText, "Canon EOS R6")
        e.model = ""
        XCTAssertEqual(e.cameraText, "Canon")
    }

    func testDataSizeAndDimensions() {
        XCTAssertEqual(ItalianFormat.dataSize(512), "512 byte")
        XCTAssertEqual(ItalianFormat.dataSize(12_340_000), "12,3 MB")
        XCTAssertEqual(ItalianFormat.dataSize(2_500_000_000), "2,5 GB")
        XCTAssertEqual(ItalianFormat.dimensions(width: 6000, height: 4000), "6000 × 4000  (24,0 MP)")
        XCTAssertEqual(ItalianFormat.dimensions(width: 0, height: 4000), "")
    }

    func testFileKinds() {
        XCTAssertTrue(FileKinds.isRaw("ARW"))
        XCTAssertTrue(FileKinds.isSupported("heic"))
        XCTAssertFalse(FileKinds.isSupported("xmp"))
        XCTAssertFalse(FileKinds.isSupported("mp4"))
        XCTAssertEqual(FileKinds.sorted(["xmp", "arw", "jpg", "png"]), ["jpg", "png", "arw", "xmp"])
        XCTAssertEqual(FileKinds.label("arw"), "RAW (ARW)")
    }
}
