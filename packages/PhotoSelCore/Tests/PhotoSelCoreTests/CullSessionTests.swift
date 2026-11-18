import XCTest
@testable import PhotoSelCore

final class CullSessionTests: XCTestCase {
    func testRatingAutoAdvanceAndUndo() {
        var s = CullSession(photos: makePhotos([0, 10, 20, 30]))
        XCTAssertEqual(s.currentRow, 0)
        XCTAssertEqual(s.setFlag(1), 0)
        XCTAssertEqual(s.currentRow, 1)          // auto advance
        XCTAssertEqual(s.setStars(3), 1)
        XCTAssertEqual(s.currentRow, 2)
        XCTAssertEqual(s.counts.picks, 1)
        XCTAssertEqual(s.counts.starred, 1)
        XCTAssertEqual(s.counts.unflagged, 3)

        XCTAssertEqual(s.undo(), 1)
        XCTAssertEqual(s.currentRow, 1)
        XCTAssertEqual(s.photo(uid: 1)?.stars, 0)
        XCTAssertEqual(s.undo(), 0)
        XCTAssertEqual(s.photo(uid: 0)?.flag, 0)
        XCTAssertFalse(s.canUndo)
        XCTAssertNil(s.undo())
    }

    func testNoAutoAdvanceOnClearAndLastPhoto() {
        var s = CullSession(photos: makePhotos([0, 10]), autoAdvance: true)
        s.last()
        s.setFlag(-1)
        XCTAssertEqual(s.currentRow, 1)
        s.toggleFlag(-1)                          // clear
        XCTAssertEqual(s.current?.flag, 0)
        s.first()
        s.autoAdvance = false
        s.setFlag(1)
        XCTAssertEqual(s.currentRow, 0)
        XCTAssertNil(s.setFlag(1))               // unchanged
    }

    func testStarsRecoverRejected() {
        var s = CullSession(photos: makePhotos([0]), autoAdvance: false)
        s.setFlag(-1)
        s.setStars(2)
        XCTAssertEqual(s.current?.flag, 0)
        XCTAssertEqual(s.current?.stars, 2)
        s.setStars(9)
        XCTAssertEqual(s.current?.stars, 5)
    }

    func testLabelsAndRotation() {
        var s = CullSession(photos: makePhotos([0]))
        s.toggleLabel(2)
        XCTAssertEqual(s.current?.label, 2)
        s.toggleLabel(2)
        XCTAssertEqual(s.current?.label, 0)
        s.rotate(-1)
        XCTAssertEqual(s.current?.rotation, 270)
        s.rotate(1); s.rotate(1)
        XCTAssertEqual(s.current?.rotation, 90)
    }

    func testFilterKeepsOrFindsNearest() {
        var s = CullSession(photos: makePhotos([0, 10, 20, 30]), autoAdvance: false)
        s.select(row: 1); s.setFlag(1)
        s.select(row: 3); s.setFlag(1)
        s.select(row: 2)
        s.setFilter(.picks)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.current?.uid, 3)         // next visible after uid 2
        s.setFilter(.all)
        XCTAssertEqual(s.current?.uid, 3)
        s.select(row: 3)
        s.setFilter(.unflagged)
        XCTAssertEqual(s.current?.uid, 2)         // nothing after: last visible
        s.setFilter(.rejects)
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.current)
        XCTAssertEqual(s.currentRow, -1)
    }

    func testInitFallsBackToAllAndKeepsName() {
        let photos = makePhotos([0, 10, 20])
        let s = CullSession(photos: photos, filter: .picks, keepIdentity: photos[2].identity)
        XCTAssertEqual(s.filter, .all)
        XCTAssertEqual(s.current?.baseName, "P2")
        XCTAssertTrue(CullSession.empty.isEmpty)
    }

    func testNextUnflagged() {
        var s = CullSession(photos: makePhotos([0, 10, 20]), autoAdvance: false)
        s.select(row: 1); s.setFlag(1)
        s.first()
        XCTAssertTrue(s.nextUnflagged())
        XCTAssertEqual(s.currentRow, 2)
        XCTAssertFalse(s.nextUnflagged())
    }

    func testCompareWindowInsideBurst() {
        // burst of 5 (0...2 s), then 2 single photos
        var s = CullSession(photos: makePhotos([0, 0.5, 1, 1.5, 2, 10, 20]), compareSize: 3)
        XCTAssertEqual(s.compareRows, [0, 1, 2])
        s.select(row: 2)
        XCTAssertEqual(s.compareRows, [0, 1, 2])   // current still inside: window stays
        s.select(row: 3)
        XCTAssertEqual(s.compareRows, [2, 3, 4])   // forward, clamped to the burst end
        s.select(row: 4)
        XCTAssertEqual(s.compareRows, [2, 3, 4])
        s.select(row: 1)
        XCTAssertEqual(s.compareRows, [0, 1, 2])   // backward
        s.select(row: 5)
        XCTAssertEqual(s.compareRows, [4, 5, 6])   // single photo: every photo is a candidate
        s.setCompareSize(9)
        XCTAssertEqual(s.compareSize, 4)
        XCTAssertEqual(s.compareRows, [3, 4, 5, 6])
    }

    func testSharpnessAndBurstBest() {
        var s = CullSession(photos: makePhotos([0, 0.5, 1, 10]))
        s.setAnalysis(uid: 0, sharpness: 100, histogram: [])
        s.setAnalysis(uid: 1, sharpness: 400, histogram: [])
        s.setAnalysis(uid: 2, sharpness: 50, histogram: [])
        s.setAnalysis(uid: 3, sharpness: 900, histogram: [])
        XCTAssertTrue(s.isBurstBest(uid: 1))
        XCTAssertFalse(s.isBurstBest(uid: 0))
        XCTAssertFalse(s.isBurstBest(uid: 3))       // not in a burst
        XCTAssertEqual(s.burstSharpness(uid: 0), 0.25, accuracy: 1e-9)
        XCTAssertEqual(s.sharpness(uid: 1), (400.0 / 900).squareRoot(), accuracy: 1e-9)
        s.finalizeSharpness()                       // 90th percentile of 4 values = index 3 -> 900
        XCTAssertEqual(s.sharpness(uid: 3), 1, accuracy: 1e-9)
        XCTAssertEqual(s.analyzedCount, 4)
    }

    func testPreloadOrder() {
        var s = CullSession(photos: makePhotos([0, 10, 20, 30, 40, 50]))
        s.select(row: 2)
        XCTAssertEqual(s.preloadUIDs, [3, 4, 1, 5, 0])
    }
}
