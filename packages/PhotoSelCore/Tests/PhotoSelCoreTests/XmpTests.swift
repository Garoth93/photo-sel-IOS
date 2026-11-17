import XCTest
@testable import PhotoSelCore

final class XmpTests: XCTestCase {
    func testSkipWhenNothingToSave() {
        XCTAssertEqual(Xmp.render(existing: nil, rating: XmpRating()), .skip)
    }

    func testRoundTripFromTemplate() throws {
        let rating = XmpRating(stars: 4, flag: 1, label: 3)
        guard case .write(let xml) = Xmp.render(existing: nil, rating: rating) else { return XCTFail() }
        XCTAssertTrue(xml.contains("xmp:Rating=\"4\""))
        XCTAssertTrue(xml.contains("xmp:Label=\"Green\""))
        XCTAssertTrue(xml.contains("xmlns:photosel="))
        XCTAssertEqual(Xmp.parse(xml), XmpRating(stars: 4, flag: 1, label: 3, found: true))
    }

    func testRejectedKeepsStars() {
        guard case .write(let xml) = Xmp.render(existing: nil, rating: XmpRating(stars: 2, flag: -1)) else { return XCTFail() }
        XCTAssertTrue(xml.contains("xmp:Rating=\"-1\""))
        XCTAssertEqual(Xmp.parse(xml), XmpRating(stars: 2, flag: -1, label: 0, found: true))
    }

    func testUpdatesLightroomSidecarKeepingOtherSettings() {
        let lr = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            xmp:Rating="3"
            xmp:Label="Red"
            crs:Exposure2012="+0.35">
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
        XCTAssertEqual(Xmp.parse(lr), XmpRating(stars: 3, flag: 0, label: 1, found: true))
        guard case .write(let xml) = Xmp.render(existing: lr, rating: XmpRating(stars: 5, flag: 1, label: 0)) else { return XCTFail() }
        XCTAssertTrue(xml.contains("crs:Exposure2012=\"+0.35\""))
        XCTAssertTrue(xml.contains("xmp:Rating=\"5\""))
        XCTAssertTrue(xml.contains("xmp:Label=\"\""))   // label removed but key kept, like the Qt app
        XCTAssertEqual(xml.components(separatedBy: "xmlns:xmp=").count, 2)  // namespace not duplicated
        XCTAssertEqual(Xmp.parse(xml), XmpRating(stars: 5, flag: 1, label: 0, found: true))
    }

    func testElementSyntax() {
        let xml = """
        <x:xmpmeta><rdf:RDF><rdf:Description rdf:about="">
        <xmp:Rating>2</xmp:Rating><xmp:Label>Blue</xmp:Label>
        </rdf:Description></rdf:RDF></x:xmpmeta>
        """
        XCTAssertEqual(Xmp.parse(xml), XmpRating(stars: 2, flag: 0, label: 4, found: true))
        guard case .write(let out) = Xmp.render(existing: xml, rating: XmpRating(stars: 1, flag: 0, label: 4)) else { return XCTFail() }
        XCTAssertTrue(out.contains("<xmp:Rating>1</xmp:Rating>"))
    }

    func testInvalidFile() {
        XCTAssertEqual(Xmp.render(existing: "garbage", rating: XmpRating(stars: 1)), .invalid)
    }
}
