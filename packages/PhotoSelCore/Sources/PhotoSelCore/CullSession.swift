import Foundation

public enum PhotoFilter: Int, CaseIterable, Sendable, Codable {
    case all = 0, unflagged, picks, rejects, starred

    public var title: String {
        switch self {
        case .all: return "Tutte"
        case .unflagged: return "Da valutare"
        case .picks: return "Tenute"
        case .rejects: return "Scartate"
        case .starred: return "Con stelle"
        }
    }

    public func passes(_ p: Photo) -> Bool {
        switch self {
        case .all: return true
        case .unflagged: return p.flag == 0
        case .picks: return p.flag == 1
        case .rejects: return p.flag == -1
        case .starred: return p.stars > 0
        }
    }
}

public struct CullCounts: Equatable, Sendable {
    public var total = 0, picks = 0, rejects = 0, unflagged = 0, starred = 0

    public func count(for f: PhotoFilter) -> Int {
        switch f {
        case .all: return total
        case .unflagged: return unflagged
        case .picks: return picks
        case .rejects: return rejects
        case .starred: return starred
        }
    }
}

/// State of a culling session on one folder: filter, current photo, ratings
/// with undo, compare window, bursts and sharpness. Port of `AppController` +
/// `PhotoModel` of the Qt app, without UI and I/O: the app persists the XMP of
/// the uid returned by the rating methods.
public struct CullSession: Sendable {
    public private(set) var photos: [Photo]          // index == uid
    public private(set) var visible: [Int] = []      // uids of the visible rows
    private var rowOfUid: [Int: Int] = [:]
    public private(set) var filter: PhotoFilter = .all
    public private(set) var currentRow = -1
    public private(set) var compareRows: [Int] = []
    public private(set) var counts = CullCounts()
    public var autoAdvance: Bool
    public private(set) var compareSize: Int

    struct UndoEntry: Sendable { var uid: Int, stars: Int, flag: Int, label: Int }
    private var undoStack: [UndoEntry] = []
    public static let undoLimit = 500

    private var burstBest: [Int: Int] = [:]
    private var burstMax: [Int: Double] = [:]
    private var sharpRef: Double = 0

    /// `photos` must already be finalized (uid == index, see `PhotoGrouper.finalize`).
    /// With a filter that hides everything, falls back to "all" like the Qt app.
    public init(photos: [Photo], filter: PhotoFilter = .all, keepBaseName: String? = nil,
                autoAdvance: Bool = true, compareSize: Int = 3) {
        self.photos = photos
        self.autoAdvance = autoAdvance
        self.compareSize = min(max(compareSize, 2), 4)
        self.filter = filter
        rebuildVisible()
        if filter != .all && visible.isEmpty {
            self.filter = .all
            rebuildVisible()
        }
        refreshCounts()
        var row = 0
        if let keep = keepBaseName, let r = visible.firstIndex(where: { self.photos[$0].baseName == keep }) {
            row = r
        }
        select(row: visible.isEmpty ? -1 : row)
    }

    public static var empty: CullSession { CullSession(photos: []) }

    // MARK: - Access

    public var count: Int { visible.count }
    public var totalCount: Int { photos.count }
    public var isEmpty: Bool { visible.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }

    public func photo(atRow row: Int) -> Photo? {
        guard row >= 0, row < visible.count else { return nil }
        return photos[visible[row]]
    }

    public func photo(uid: Int) -> Photo? {
        uid >= 0 && uid < photos.count ? photos[uid] : nil
    }

    public func uid(atRow row: Int) -> Int? {
        row >= 0 && row < visible.count ? visible[row] : nil
    }

    public func row(ofUID uid: Int) -> Int? { rowOfUid[uid] }

    public var current: Photo? { photo(atRow: currentRow) }

    /// Rows to preload around the current one (next ones first: one scrolls forward).
    public var preloadUIDs: [Int] {
        [1, 2, -1, 3, -2].compactMap { uid(atRow: currentRow + $0) }
    }

    // MARK: - Navigation

    public mutating func select(row newRow: Int) {
        let row = visible.isEmpty ? -1 : min(max(newRow, 0), visible.count - 1)
        guard row != currentRow else {
            if compareRows.isEmpty { updateCompare(previousRow: currentRow) }
            return
        }
        let previous = currentRow
        currentRow = row
        updateCompare(previousRow: previous)
    }

    public mutating func select(uid: Int) {
        if let r = rowOfUid[uid] { select(row: r) }
    }

    public mutating func next() { step(1) }
    public mutating func previous() { step(-1) }
    public mutating func step(_ delta: Int) {
        if currentRow >= 0 { select(row: currentRow + delta) }
    }
    public mutating func first() { select(row: 0) }
    public mutating func last() { select(row: visible.count - 1) }

    /// Next photo without a flag after the current one. Returns false when there is none.
    @discardableResult
    public mutating func nextUnflagged() -> Bool {
        guard currentRow + 1 < visible.count else { return false }
        for r in (currentRow + 1)..<visible.count where photos[visible[r]].flag == 0 {
            select(row: r)
            return true
        }
        return false
    }

    // MARK: - Filter

    /// Pressing the same filter again refreshes the list (photos just rated leave it).
    public mutating func setFilter(_ f: PhotoFilter) {
        let keepUid = uid(atRow: currentRow)
        filter = f
        rebuildVisible()
        var row = -1
        if let keep = keepUid {
            if let r = rowOfUid[keep] {
                row = r
            } else {
                // nearest following photo still visible, otherwise the last one before
                row = visible.firstIndex { $0 > keep } ?? (visible.isEmpty ? -1 : visible.count - 1)
            }
        } else if !visible.isEmpty {
            row = 0
        }
        currentRow = -1
        compareRows = []
        select(row: row)
    }

    private mutating func rebuildVisible() {
        visible = photos.filter { filter.passes($0) }.map(\.uid)
        rowOfUid = Dictionary(uniqueKeysWithValues: visible.enumerated().map { ($1, $0) })
    }

    private mutating func refreshCounts() {
        var c = CullCounts()
        c.total = photos.count
        for p in photos {
            if p.flag == 1 { c.picks += 1 } else if p.flag == -1 { c.rejects += 1 } else { c.unflagged += 1 }
            if p.stars > 0 { c.starred += 1 }
        }
        counts = c
    }

    // MARK: - Rating
    // Every method returns the uid whose rating changed (to be saved in its XMP),
    // or nil when nothing changed.

    @discardableResult
    private mutating func applyRating(uid: Int, stars: Int, flag: Int, label: Int, recordUndo: Bool) -> Bool {
        let p = photos[uid]
        if p.stars == stars && p.flag == flag && p.label == label { return false }
        if recordUndo {
            undoStack.append(UndoEntry(uid: uid, stars: p.stars, flag: p.flag, label: p.label))
            if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        }
        photos[uid].stars = stars
        photos[uid].flag = flag
        photos[uid].label = label
        refreshCounts()
        return true
    }

    private mutating func afterRating() {
        if autoAdvance && currentRow < visible.count - 1 { next() }
    }

    /// 1 keep, -1 reject, 0 clear.
    @discardableResult
    public mutating func setFlag(_ flag: Int) -> Int? {
        guard let p = current else { return nil }
        let changed = applyRating(uid: p.uid, stars: p.stars, flag: min(max(flag, -1), 1), label: p.label, recordUndo: true)
        if flag != 0 { afterRating() }
        return changed ? p.uid : nil
    }

    @discardableResult
    public mutating func toggleFlag(_ flag: Int) -> Int? {
        guard let p = current else { return nil }
        if p.flag == flag {
            return applyRating(uid: p.uid, stars: p.stars, flag: 0, label: p.label, recordUndo: true) ? p.uid : nil
        }
        return setFlag(flag)
    }

    /// Giving stars to a rejected photo "recovers" it.
    @discardableResult
    public mutating func setStars(_ value: Int) -> Int? {
        guard let p = current else { return nil }
        let stars = min(max(value, 0), 5)
        let flag = (stars > 0 && p.flag == -1) ? 0 : p.flag
        let changed = applyRating(uid: p.uid, stars: stars, flag: flag, label: p.label, recordUndo: true)
        if stars > 0 { afterRating() }
        return changed ? p.uid : nil
    }

    @discardableResult
    public mutating func setLabel(_ label: Int) -> Int? {
        guard let p = current else { return nil }
        return applyRating(uid: p.uid, stars: p.stars, flag: p.flag, label: min(max(label, 0), 5), recordUndo: true) ? p.uid : nil
    }

    @discardableResult
    public mutating func toggleLabel(_ label: Int) -> Int? {
        guard let p = current else { return nil }
        return setLabel(p.label == label ? 0 : label)
    }

    /// View-only rotation: +1 clockwise, -1 counter-clockwise.
    public mutating func rotate(_ direction: Int) {
        guard let p = current else { return }
        photos[p.uid].rotation = ((p.rotation + (direction >= 0 ? 90 : -90)) % 360 + 360) % 360
    }

    /// Undoes the last rating; returns the uid to save again.
    @discardableResult
    public mutating func undo() -> Int? {
        guard let e = undoStack.popLast(), e.uid < photos.count else { return nil }
        applyRating(uid: e.uid, stars: e.stars, flag: e.flag, label: e.label, recordUndo: false)
        if let r = rowOfUid[e.uid] { select(row: r) }
        return e.uid
    }

    /// Records the sidecar file after the app created it.
    public mutating func setSidecar(_ url: URL?, uid: Int) {
        guard uid >= 0, uid < photos.count else { return }
        photos[uid].files[FileKinds.sidecar] = url
    }

    public var extensions: [String] { PhotoGrouper.extensions(of: photos) }

    // MARK: - Compare window

    public mutating func setCompareSize(_ n: Int) {
        let size = min(max(n, 2), 4)
        guard size != compareSize else { return }
        compareSize = size
        compareRows = []
        updateCompare(previousRow: currentRow)
    }

    /// Candidates: visible members of the same burst, otherwise all the photos.
    /// The window does not move while the current photo stays inside it.
    private mutating func updateCompare(previousRow: Int) {
        guard let cur = current else {
            compareRows = []
            return
        }
        let candidates: [Int] = cur.isBurst
            ? visible.indices.filter { photos[visible[$0]].burstId == cur.burstId }
            : Array(visible.indices)
        let pos = candidates.firstIndex(of: currentRow) ?? 0
        let size = min(compareSize, candidates.count)

        if !compareRows.isEmpty && compareRows.count == size
            && compareRows.allSatisfy({ candidates.contains($0) }) && compareRows.contains(currentRow) {
            return
        }
        let forward = previousRow < 0 || currentRow >= previousRow
        var start = forward ? pos : pos - size + 1
        start = min(max(start, 0), max(0, candidates.count - size))
        compareRows = Array(candidates[start..<(start + size)])
    }

    // MARK: - Sharpness

    public mutating func setAnalysis(uid: Int, sharpness: Double, histogram: [Float]) {
        guard uid >= 0, uid < photos.count else { return }
        photos[uid].analyzed = true
        photos[uid].sharpness = sharpness
        photos[uid].histogram = histogram
        if sharpness > sharpRef { sharpRef = sharpness }   // provisional reference: max so far
        if photos[uid].burstId >= 0 { recomputeBurstBest(photos[uid].burstId) }
    }

    /// Final reference: 90th percentile, so one outlier does not flatten everything.
    public mutating func finalizeSharpness() {
        let v = photos.filter { $0.analyzed && $0.sharpness > 0 }.map(\.sharpness).sorted()
        guard !v.isEmpty else { return }
        let idx = min(v.count - 1, Int((Double(v.count) * 0.9).rounded(.down)))
        sharpRef = v[idx]
    }

    private mutating func recomputeBurstBest(_ burstId: Int) {
        var best = -1.0
        var bestUid = -1
        for p in photos where p.burstId == burstId && p.analyzed && p.sharpness > best {
            best = p.sharpness
            bestUid = p.uid
        }
        burstBest[burstId] = bestUid
        burstMax[burstId] = best
    }

    public var analyzedCount: Int { photos.lazy.filter(\.analyzed).count }

    /// 0...1, relative to the whole folder.
    public func sharpness(uid: Int) -> Double {
        guard let p = photo(uid: uid), p.analyzed, sharpRef > 0 else { return 0 }
        return min(1, (p.sharpness / sharpRef).squareRoot())
    }

    /// 0...1, relative to the sharpest photo of the same burst.
    public func burstSharpness(uid: Int) -> Double {
        guard let p = photo(uid: uid), p.analyzed, let mx = burstMax[p.burstId], mx > 0 else { return 0 }
        return p.sharpness / mx
    }

    /// True for the sharpest photo of its burst (◆).
    public func isBurstBest(uid: Int) -> Bool {
        guard let p = photo(uid: uid), p.isBurst else { return false }
        return burstBest[p.burstId] == uid
    }
}
