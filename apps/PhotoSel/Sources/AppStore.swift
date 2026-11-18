import Foundation
import Observation
import PhotoSelCore
import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

enum ZoomCommand: Equatable { case toggle, zoomIn, zoomOut }

struct ZoomRequest: Equatable {
    var id = 0
    var command = ZoomCommand.toggle
}

enum SheetKind: String, Identifiable {
    case export, settings, help
    var id: String { rawValue }
}

/// Thread-safe cancel flag for the export running off the main thread.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// App state: opened folder, culling session (PhotoSelCore), background
/// analysis, ratings saved in XMP sidecars, export. Port of `AppController`.
@MainActor
@Observable
final class AppStore {
    var settings: AppSettings {
        didSet { if settings != oldValue { saveSettings() } }
    }
    private(set) var folder: URL?
    private(set) var session = CullSession.empty
    private(set) var scanning = false
    private(set) var analysisDone = 0
    private(set) var analysisTotal = 0
    var viewMode: ViewMode = .loupe
    var chromeHidden = false
    var showFolderPicker = false
    var activeSheet: SheetKind?
    private(set) var toast: ToastMessage?
    private(set) var zoomRequest = ZoomRequest()
    /// Columns of the grid, used by ↑ ↓.
    var gridColumns = 4
    /// Multi-selection in the grid (to send many photos to Lightroom).
    var selecting = false
    private(set) var selection = PhotoSelection()

    // Export
    private(set) var exporting = false
    private(set) var exportProgress: ExportProgress?
    private(set) var exportMessage: String?
    private(set) var exportSucceeded = false

    @ObservationIgnored let images = ImageService()
    @ObservationIgnored private let xmp = XmpWriter()
    @ObservationIgnored private let settingsStore: JSONFileStore<AppSettings>
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var accessing: URL?
    @ObservationIgnored private var exportCancel = CancelFlag()
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Export folder chosen outside the default subfolder: not scanned as photos.
    @ObservationIgnored private var customDestination: URL?

    init() {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photoSel", isDirectory: true)
            .appendingPathComponent("settings.json")
        settingsStore = JSONFileStore(url: url)
        settings = (try? settingsStore.load()) ?? AppSettings()
    }

    private func saveSettings() {
        try? settingsStore.save(settings)
    }

    // MARK: - Derived state

    var hasFolder: Bool { folder != nil }
    var folderName: String { folder?.lastPathComponent ?? "" }
    var current: Photo? { session.current }
    var analyzing: Bool { analysisTotal > 0 && analysisDone < analysisTotal }
    var counts: CullCounts { session.counts }

    // MARK: - Folders

    func openFolder(pickedURL url: URL) {
        closeFolder()
        let ok = url.startAccessingSecurityScopedResource()
        accessing = ok ? url : nil
        guard isDirectory(url) else {
            stopAccess()
            showToast("La cartella \(url.lastPathComponent) non è leggibile")
            return
        }
        open(url)
    }

    func openRecent(_ recent: RecentFolder) {
        guard let url = FolderAccess.resolve(recent.bookmark) else {
            showToast("La cartella \(recent.name) non è più disponibile. Riaprila da File.")
            return
        }
        closeFolder()
        let ok = url.startAccessingSecurityScopedResource()
        accessing = ok ? url : nil
        guard isDirectory(url) else {
            stopAccess()
            showToast("La cartella \(recent.name) non è più disponibile. Se è su una scheda, inseriscila e riaprila da File.")
            return
        }
        open(url)
    }

    private func open(_ url: URL) {
        folder = url
        viewMode = .loupe
        chromeHidden = false
        if let bookmark = FolderAccess.bookmark(for: url) {
            let recent = RecentFolder(name: url.lastPathComponent, path: url.path, bookmark: bookmark, opened: Date())
            settings.recents = RecentFolder.adding(recent, to: settings.recents)
        }
        startScan(keepIdentity: nil)
    }

    func forgetRecent(_ recent: RecentFolder) {
        settings.recents.removeAll { $0.path == recent.path }
    }

    func closeFolder() {
        scanTask?.cancel()
        analysisTask?.cancel()
        generation += 1
        xmp.flush()
        stopAccess()
        folder = nil
        session = .empty
        endSelection()
        scanning = false
        analysisDone = 0
        analysisTotal = 0
        exportMessage = nil
        images.clearMemory()
    }

    func reload() {
        guard hasFolder else { return }
        startScan(keepIdentity: current?.identity)
    }

    private func stopAccess() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }

    private func startScan(keepIdentity: String?) {
        guard let folder else { return }
        scanTask?.cancel()
        analysisTask?.cancel()
        generation += 1
        let gen = generation
        scanning = true
        endSelection()
        analysisDone = 0
        analysisTotal = 0
        let preferRaw = settings.preferRaw
        let gap = settings.burstGapMs
        let filter = session.filter
        // the app's own output folders are not photos to rate
        var excluded = [
            folder.appendingPathComponent(ExportOptions.cleanFolderName(settings.export.subfolder, fallback: "selezionate")),
            folder.appendingPathComponent(ExportOptions.cleanFolderName(settings.export.rejectFolder, fallback: "da_eliminare")),
        ]
        if let customDestination { excluded.append(customDestination) }

        scanTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try AppStore.scan(folder: folder, excluding: excluded, preferRaw: preferRaw, burstGapMs: gap) }
            }.value
            guard gen == generation else { return }
            scanning = false
            switch result {
            case .success(let photos):
                session = CullSession(photos: photos, filter: filter, keepIdentity: keepIdentity,
                                      autoAdvance: settings.autoAdvance, compareSize: settings.compareSize)
                didMove()
                startAnalysis()
            case .failure(let error):
                session = .empty
                showToast("Impossibile leggere la cartella: \(error.localizedDescription)")
            }
        }
    }

    /// Lists the folder and its subfolders, pairs JPG/RAW/XMP also across
    /// folders, reads metadata and XMP ratings. Runs off the main thread.
    nonisolated private static func scan(folder: URL, excluding: [URL], preferRaw: Bool, burstGapMs: Int) throws -> [Photo] {
        let entries = try FolderScanner.listFiles(in: folder, excluding: excluding)
        var photos = PhotoGrouper.group(entries, preferRaw: preferRaw) { url in
            ImageService.metadata(url).exif.captured
        }
        for i in photos.indices {
            if Task.isCancelled { break }
            guard let url = photos[i].displayURL else { continue }
            var meta = ImageService.metadata(url)
            if meta.exif.isEmpty, let raw = photos[i].rawURL, raw != url {
                // JPG without EXIF but with a RAW next to it: take the data from the RAW
                let rawMeta = ImageService.metadata(raw)
                meta.exif = rawMeta.exif
            }
            photos[i].exif = meta.exif
            photos[i].pixelWidth = meta.pixelWidth
            photos[i].pixelHeight = meta.pixelHeight
            if let captured = meta.exif.captured { photos[i].sortTime = captured }
            if let xmpURL = photos[i].files[FileKinds.sidecar], let data = try? Data(contentsOf: xmpURL) {
                let r = Xmp.parse(String(decoding: data, as: UTF8.self))
                photos[i].stars = r.stars
                photos[i].flag = r.flag
                photos[i].label = r.label
            }
        }
        return PhotoGrouper.finalize(photos, burstGapMs: burstGapMs)
    }

    // MARK: - Analysis (sharpness + histogram)

    private func startAnalysis() {
        analysisTask?.cancel()
        let gen = generation
        let all = session.photos
        guard !all.isEmpty else { return }
        // thumbnails are also used by the views: start from the current photo
        let start = current?.uid ?? 0
        let jobs: [(Int, URL)] = (0..<all.count).compactMap { i in
            let p = all[(start + i) % all.count]
            return p.displayURL.map { (p.uid, $0) }
        }
        analysisDone = 0
        analysisTotal = jobs.count
        let images = self.images
        let width = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)

        analysisTask = Task {
            var pending: [(Int, Double, [Float])] = []
            var done = 0
            var lastFlush = Date()
            await withTaskGroup(of: (Int, Double, [Float])?.self) { group in
                var next = 0
                func job(_ j: (Int, URL)) -> @Sendable () async -> (Int, Double, [Float])? {
                    { Task.isCancelled ? nil : images.analyze(j.1).map { (j.0, $0.sharpness, $0.histogram) } }
                }
                while next < min(width, jobs.count) {
                    group.addTask(operation: job(jobs[next]))
                    next += 1
                }
                for await r in group {
                    if Task.isCancelled || gen != generation {
                        group.cancelAll()
                        return
                    }
                    if let r { pending.append(r) }
                    done += 1
                    if next < jobs.count {
                        group.addTask(operation: job(jobs[next]))
                        next += 1
                    }
                    if done == jobs.count || Date().timeIntervalSince(lastFlush) > 0.4 {
                        var s = session
                        for (uid, sharp, hist) in pending { s.setAnalysis(uid: uid, sharpness: sharp, histogram: hist) }
                        if done == jobs.count { s.finalizeSharpness() }
                        session = s
                        analysisDone = done
                        pending.removeAll()
                        lastFlush = Date()
                    }
                }
            }
        }
    }

    // MARK: - Navigation

    private func didMove() {
        let urls = session.preloadUIDs.compactMap { session.photo(uid: $0)?.displayURL }
        images.preload(urls)
    }

    func select(row: Int) { session.select(row: row); didMove() }
    func select(uid: Int) { session.select(uid: uid); didMove() }
    func next() { session.next(); didMove() }
    func previous() { session.previous(); didMove() }
    func step(_ delta: Int) { session.step(delta); didMove() }
    func first() { session.first(); didMove() }
    func last() { session.last(); didMove() }

    func nextUnflagged() {
        if session.nextUnflagged() { didMove() } else { showToast("Nessuna foto da valutare dopo questa") }
    }

    /// Pressing the same filter again refreshes the list (the photos just rated leave it).
    func setFilter(_ f: PhotoFilter) {
        session.setFilter(f)
        didMove()
    }

    // MARK: - Rating

    private func rate(_ change: (inout CullSession) -> Int?) {
        var s = session
        let uid = change(&s)
        session = s
        if let uid { persist(uid: uid) }
        didMove()
    }

    func setFlag(_ flag: Int) { rate { $0.setFlag(flag) } }
    func toggleFlag(_ flag: Int) { rate { $0.toggleFlag(flag) } }
    func setStars(_ stars: Int) { rate { $0.setStars(stars) } }
    func setLabel(_ label: Int) { rate { $0.setLabel(label) } }
    func toggleLabel(_ label: Int) { rate { $0.toggleLabel(label) } }
    func rotate(_ direction: Int) { session.rotate(direction) }

    var canUndo: Bool { session.canUndo }

    func undo() {
        var s = session
        guard let uid = s.undo() else { return }
        session = s
        persist(uid: uid)
        didMove()
        if let name = session.photo(uid: uid)?.baseName { showToast("Annullata la modifica su \(name)") }
    }

    private func persist(uid: Int) {
        guard settings.writeXmp, let p = session.photo(uid: uid) else { return }
        let gen = generation
        let rating = XmpRating(stars: p.stars, flag: p.flag, label: p.label)
        xmp.write(rating, to: p.xmpURL) { [weak self] url, message in
            guard let self, gen == self.generation else { return }
            if let message { self.showToast(message) }
            if let url, self.session.photo(uid: uid)?.files[FileKinds.sidecar] == nil {
                self.session.setSidecar(url, uid: uid)
            }
        }
    }

    // MARK: - Settings with side effects

    func setAutoAdvance(_ on: Bool) {
        settings.autoAdvance = on
        session.autoAdvance = on
    }

    func setPreferRaw(_ on: Bool) {
        guard on != settings.preferRaw else { return }
        settings.preferRaw = on
        reload()
    }

    func setBurstGap(_ ms: Int) {
        let v = AppSettings.clampGap(ms)
        guard v != settings.burstGapMs else { return }
        settings.burstGapMs = v
        reload()
    }

    func setCompareSize(_ n: Int) {
        settings.compareSize = min(max(n, 2), 4)
        session.setCompareSize(n)
    }

    func cycleBackground() {
        settings.loupeBackground = AppSettings.wrapBackground(settings.loupeBackground + 1)
    }

    func zoom(_ command: ZoomCommand) {
        zoomRequest = ZoomRequest(id: zoomRequest.id + 1, command: command)
    }

    // MARK: - Toast

    func showToast(_ text: String) {
        toast = ToastMessage(text: text)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - Export

    var extensions: [String] { session.extensions }

    func exportCount(_ selection: ExportSelection, minStars: Int) -> Int {
        ExportPlanner.count(session.photos, selection: selection, minStars: minStars)
    }

    func defaultExportOptions() -> ExportOptions {
        var o = settings.export
        o.formats = o.validFormats(available: extensions)
        return o
    }

    func clearExportMessage() {
        exportMessage = nil
        exportSucceeded = false
    }

    /// `destination` nil = subfolder of the opened folder.
    func startExport(_ options: ExportOptions, destination: URL?) {
        guard let folder, !exporting else { return }
        var o = options
        o.subfolder = ExportOptions.cleanFolderName(o.subfolder, fallback: "selezionate")
        o.rejectFolder = ExportOptions.cleanFolderName(o.rejectFolder, fallback: "da_eliminare")
        // remember the choices, but never a format list empty by mistake
        var remembered = o
        if remembered.formats.isEmpty { remembered.formats = settings.export.formats }
        settings.export = remembered

        let dest = destination ?? folder.appendingPathComponent(o.subfolder, isDirectory: true)
        if let destination { customDestination = destination }
        let plan: ExportPlan
        switch ExportPlanner.plan(photos: session.photos, options: o, folder: folder, destination: dest) {
        case .success(let p): plan = p
        case .failure(let e):
            exportMessage = e.message
            exportSucceeded = false
            return
        }

        xmp.flush()   // sidecars must be complete before they are copied
        exporting = true
        exportMessage = nil
        exportProgress = ExportProgress(done: 0, total: plan.totalFiles, fileName: "")
        let cancel = CancelFlag()
        exportCancel = cancel
        let destAccess = destination?.startAccessingSecurityScopedResource() ?? false
        let saveToPhotos = o.saveToPhotos
        let reloads = o.move || (o.moveRejects && !plan.rejects.isEmpty)

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ExportResult in
                var last = Date.distantPast
                return ExportRunner.run(plan, isCancelled: { cancel.isSet }) { p in
                    let now = Date()
                    guard now.timeIntervalSince(last) > 0.1 || p.fileName.isEmpty else { return }
                    last = now
                    Task { @MainActor [weak self] in self?.exportProgress = p }
                }
            }.value
            var message = result.message
            var ok = result.ok
            if saveToPhotos && !result.exported.isEmpty && !result.cancelled {
                exportProgress = ExportProgress(done: plan.totalFiles, total: plan.totalFiles, fileName: "Libreria Foto…")
                let saved = await PhotoLibrarySaver.save(result.exported)
                message += saved.saved == 1 ? ". 1 foto aggiunta a Foto" : ". \(saved.saved) foto aggiunte a Foto"
                if let err = saved.error {
                    message += ". \(err)"
                    ok = false
                }
            }
            if destAccess { destination?.stopAccessingSecurityScopedResource() }
            exporting = false
            exportProgress = nil
            exportMessage = message
            exportSucceeded = ok
            showToast(message)
            if reloads { reload() }
        }
    }

    func cancelExport() { exportCancel.set() }

    /// "DCIM/100MSDCF · RAW": where the files of a photo are, relative to the opened folder.
    func folderText(_ p: Photo) -> String {
        guard let folder else { return "" }
        return p.directories.map { dir -> String in
            let rel = PhotoGrouper.relativePath(of: dir, to: folder)
            return rel.isEmpty ? folder.lastPathComponent : rel
        }.joined(separator: " · ")
    }

    // MARK: - Selection and sharing (Lightroom)

    func beginSelection() {
        selecting = true
        viewMode = .grid
        selection.clear()
        if let uid = current?.uid { selection.toggle(uid) }
    }

    func endSelection() {
        selecting = false
        selection.clear()
    }

    func toggleSelected(_ uid: Int) {
        selection.toggle(uid)
        select(uid: uid)
    }

    func selectAllVisible() { selection.set(session.visible) }
    func selectPicksVisible() { selection.set(session.visible.filter { session.photo(uid: $0)?.flag == 1 }) }
    func clearSelection() { selection.clear() }

    var selectedPhotos: [Photo] { selection.photos(in: session) }

    /// Opens the share sheet with the files of the photos (Lightroom, File, AirDrop…).
    func share(_ photos: [Photo]) {
        let urls = ShareFiles.urls(for: photos, format: settings.shareFormat)
        guard !urls.isEmpty else {
            showToast("Nessun file da condividere")
            return
        }
        xmp.flush()
        SharePresenter.present(urls)
    }

    func shareCurrentOrSelection() {
        if selecting && !selection.isEmpty { share(selectedPhotos) } else if let p = current { share([p]) }
    }

    // MARK: - Cache

    var cacheSizeText: String { ItalianFormat.dataSize(images.cacheSizeBytes) }

    func clearThumbnailCache() {
        images.clearCache()
        showToast("Cache delle miniature svuotata")
    }
}
