import XCTest
@testable import PhotoSelCore

final class ExportTests: XCTestCase {
    private func photo(_ name: String, exts: [String], flag: Int = 0, stars: Int = 0, in dir: URL = folder) -> Photo {
        var p = Photo(baseName: name, folder: dir)
        for e in exts { p.files[e] = dir.appendingPathComponent("\(name).\(e.uppercased())") }
        p.displayExt = exts.first ?? ""
        p.flag = flag
        p.stars = stars
        return p
    }

    func testSelection() {
        let ps = [photo("a", exts: ["jpg"], flag: 1), photo("b", exts: ["jpg"], flag: -1, stars: 4),
                  photo("c", exts: ["jpg"], stars: 2), photo("d", exts: ["jpg"])]
        XCTAssertEqual(ExportPlanner.count(ps, selection: .picks, minStars: 1), 1)
        XCTAssertEqual(ExportPlanner.count(ps, selection: .stars, minStars: 2), 1)
        XCTAssertEqual(ExportPlanner.count(ps, selection: .notRejected, minStars: 1), 3)
        XCTAssertEqual(ExportPlanner.count(ps, selection: .all, minStars: 1), 4)
    }

    func testValidFormats() {
        var o = ExportOptions()
        XCTAssertEqual(o.validFormats(available: ["jpg", "arw", "xmp"]), ["arw"])
        XCTAssertEqual(o.validFormats(available: ["jpg", "png"]), ["jpg"])
        o.formats = ["jpg", "cr3"]
        XCTAssertEqual(o.validFormats(available: ["jpg", "arw"]), ["jpg"])
        XCTAssertEqual(o.validFormats(available: []), [])
    }

    func testPlanPerFormatFolderAndXmpNextToRaw() throws {
        var o = ExportOptions()
        o.formats = ["jpg", "arw", "xmp"]
        let dest = folder.appendingPathComponent("selezionate")
        let ps = [photo("a", exts: ["jpg", "arw", "xmp"], flag: 1), photo("b", exts: ["jpg"], flag: 1),
                  photo("c", exts: ["jpg", "arw"])]
        let plan = try ExportPlanner.plan(photos: ps, options: o, folder: folder, destination: dest).get()
        XCTAssertEqual(plan.photos.count, 2)
        XCTAssertEqual(plan.photos[0].map(\.subdir), ["jpg", "arw", "arw"])
        XCTAssertEqual(plan.photos[0].last?.source.lastPathComponent, "a.XMP")
        XCTAssertEqual(plan.photos[1].map(\.subdir), ["jpg"])
        XCTAssertEqual(plan.totalFiles, 4)
    }

    func testPlanErrors() {
        var o = ExportOptions()
        o.formats = ["jpg"]
        o.perFormatFolder = false
        let ps = [photo("a", exts: ["jpg"], flag: 1)]
        XCTAssertEqual(ExportPlanner.plan(photos: ps, options: o, folder: folder, destination: folder),
                       .failure(.sameFolder))
        o.perFormatFolder = true
        o.selection = .stars
        o.minStars = 5
        XCTAssertEqual(ExportPlanner.plan(photos: ps, options: o, folder: folder, destination: folder),
                       .failure(.nothingSelected))
    }

    func testRejectsOnly() throws {
        var o = ExportOptions()
        o.formats = []
        o.moveRejects = true
        o.rejectFolder = "  "
        let ps = [photo("a", exts: ["jpg", "arw"], flag: -1), photo("b", exts: ["jpg"])]
        let plan = try ExportPlanner.plan(photos: ps, options: o, folder: folder, destination: folder).get()
        XCTAssertEqual(plan.rejectDir?.lastPathComponent, "da_eliminare")
        XCTAssertEqual(plan.rejects.map { $0.count }, [2])
    }

    func testSuffix() {
        XCTAssertEqual(ExportPlanner.suffixed("DSC1.ARW", " (2)"), "DSC1 (2).ARW")
        XCTAssertEqual(ExportPlanner.suffixed("DSC1.ARW", ""), "DSC1.ARW")
        let dir = URL(fileURLWithPath: "/d")
        let taken: Set<String> = ["/d/x.jpg", "/d/x (1).arw"]
        let s = ExportPlanner.freeSuffix([(dir, "x.jpg"), (dir, "x.arw")]) { taken.contains($0.path) }
        XCTAssertEqual(s, " (2)")
    }

    func testRunnerCopiesMovesAndKeepsPairs() throws {
        let fm = FileManager.default
        let src = tempDir()
        defer { try? fm.removeItem(at: src) }
        for name in ["a.JPG", "a.ARW", "b.JPG", "c.JPG"] {
            try Data(name.utf8).write(to: src.appendingPathComponent(name))
        }
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: src.appendingPathComponent("a.JPG").path)

        var a = photo("a", exts: ["jpg", "arw"], flag: 1, in: src)
        a.files["jpg"] = src.appendingPathComponent("a.JPG")
        a.files["arw"] = src.appendingPathComponent("a.ARW")
        var b = photo("b", exts: ["jpg"], flag: 1, in: src)
        b.files["jpg"] = src.appendingPathComponent("b.JPG")
        var c = photo("c", exts: ["jpg"], flag: -1, in: src)
        c.files["jpg"] = src.appendingPathComponent("c.JPG")

        let dest = src.appendingPathComponent("selezionate")
        // a clash in the destination: both files of "a" get the same suffix
        try fm.createDirectory(at: dest.appendingPathComponent("arw"), withIntermediateDirectories: true)
        try Data().write(to: dest.appendingPathComponent("arw/a.ARW"))

        var o = ExportOptions()
        o.formats = ["jpg", "arw"]
        o.moveRejects = true
        let plan = try ExportPlanner.plan(photos: [a, b, c], options: o, folder: src, destination: dest).get()
        var steps: [ExportProgress] = []
        let r = ExportRunner.run(plan) { steps.append($0) }

        XCTAssertTrue(r.ok, r.firstError)
        XCTAssertEqual(r.photos, 2)
        XCTAssertEqual(r.files, 3)
        XCTAssertEqual(r.message, "2 foto esportate (3 file)")
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("jpg/a (1).JPG").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("arw/a (1).ARW").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("jpg/b.JPG").path))
        XCTAssertTrue(fm.fileExists(atPath: src.appendingPathComponent("a.JPG").path))     // copied, not moved
        XCTAssertTrue(fm.fileExists(atPath: src.appendingPathComponent("da_eliminare/c.JPG").path))
        XCTAssertFalse(fm.fileExists(atPath: src.appendingPathComponent("c.JPG").path))
        let copied = try fm.attributesOfItem(atPath: dest.appendingPathComponent("jpg/a (1).JPG").path)
        XCTAssertEqual((copied[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0, old.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(steps.last?.done, 4)
        XCTAssertEqual(r.exported.map(\.count), [2, 1])
    }

    func testRunnerCancel() throws {
        let src = tempDir()
        defer { try? FileManager.default.removeItem(at: src) }
        var o = ExportOptions()
        o.formats = ["jpg"]
        let ps = (0..<3).map { photo("p\($0)", exts: ["jpg"], flag: 1, in: src) }
        let plan = try ExportPlanner.plan(photos: ps, options: o, folder: src, destination: src.appendingPathComponent("out")).get()
        let r = ExportRunner.run(plan, isCancelled: { true })
        XCTAssertTrue(r.cancelled)
        XCTAssertEqual(r.message, "Esportazione interrotta: 0 foto esportate")
    }

    func testResultMessages() {
        var r = ExportResult()
        XCTAssertEqual(r.message, "Scartate spostate")
        r.photos = 1; r.files = 1
        XCTAssertEqual(r.message, "1 foto esportata (1 file)")
        r.failed = 2; r.firstError = "Impossibile copiare x.JPG"
        XCTAssertEqual(r.message, "1 foto esportata, 2 file non riusciti. Impossibile copiare x.JPG")
    }
}
