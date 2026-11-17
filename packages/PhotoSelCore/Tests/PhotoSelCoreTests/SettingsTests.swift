import XCTest
@testable import PhotoSelCore

final class SettingsTests: XCTestCase {
    func testLenientDecodingAndClamping() throws {
        let json = #"{"burstGapMs": 99999, "loupeBackground": -1, "compareSize": 7, "writeXmp": "yes", "export": {"minStars": 0, "selection": "bogus"}}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.burstGapMs, 5000)
        XCTAssertEqual(s.loupeBackground, 2)
        XCTAssertEqual(s.compareSize, 4)
        XCTAssertTrue(s.writeXmp)                 // invalid type -> default
        XCTAssertEqual(s.export.minStars, 1)
        XCTAssertEqual(s.export.selection, .picks)
        XCTAssertEqual(s.export.subfolder, "selezionate")
    }

    func testRoundTripThroughFileStore() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = JSONFileStore<AppSettings>(url: dir.appendingPathComponent("s/settings.json"))
        XCTAssertNil(try store.load())
        var s = AppSettings()
        s.preferRaw = true
        s.export.formats = ["arw", "xmp"]
        s.recents = [RecentFolder(name: "100MSDCF", path: "/x/DCIM/100MSDCF", bookmark: Data([1, 2]), opened: t0)]
        try store.save(s)
        XCTAssertEqual(try store.load(), s)
    }

    func testRecentsAndTexts() {
        func rf(_ p: String) -> RecentFolder { RecentFolder(name: p, path: "/v/\(p)", bookmark: Data(), opened: t0) }
        var list: [RecentFolder] = []
        for i in 0..<10 { list = RecentFolder.adding(rf("f\(i)"), to: list) }
        XCTAssertEqual(list.count, RecentFolder.limit)
        XCTAssertEqual(list.first?.name, "f9")
        list = RecentFolder.adding(rf("f5"), to: list)
        XCTAssertEqual(list.map(\.name).prefix(3), ["f5", "f9", "f8"])
        XCTAssertEqual(Set(list.map(\.path)).count, list.count)
        XCTAssertEqual(rf("x").parentName, "v")

        var s = AppSettings()
        XCTAssertEqual(s.burstGapText, "Scatti a meno di 1,0 secondi l'uno dall'altro formano una raffica.")
        s.burstGapMs = 2500
        XCTAssertTrue(s.burstGapText.contains("2,5"))
        XCTAssertEqual(ExportOptions.cleanFolderName(" a/b ", fallback: "x"), "a-b")
        XCTAssertEqual(ExportOptions.cleanFolderName("..", fallback: "x"), "x")
    }
}
