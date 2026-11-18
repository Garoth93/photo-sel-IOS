import PhotoSelCore
import SwiftUI

/// Working screen: top bar, view (single / grid / compare), info panel on the
/// right, filmstrip and rating bar at the bottom. Hardware keyboard shortcuts
/// as in the desktop app.
struct CullView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @Environment(\.horizontalSizeClass) private var sizeClass
    @FocusState private var keyboardFocus: Bool

    var body: some View {
        let hidden = store.chromeHidden
        VStack(spacing: 0) {
            if !hidden { TopBar() }
            HStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInfo {
                    Rectangle().fill(Theme.line).frame(width: 1)
                    InfoPanel().frame(width: 300)
                        .transition(.move(edge: .trailing))
                }
            }
            if !hidden && !isEmpty {
                if store.viewMode != .grid && store.settings.filmstripVisible { FilmstripView() }
                RatingBar()
            }
        }
        .background(Theme.chrome)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateScreenEdge(geo.size) }
                    .onChange(of: geo.size) { _, s in updateScreenEdge(s) }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocus)
        .onKeyPress(phases: .down) { press in handle(press) ? .handled : .ignored }
        .onAppear { keyboardFocus = true }
        .onChange(of: store.activeSheet) { _, sheet in if sheet == nil { keyboardFocus = true } }
        .sheet(item: Bindable(store).activeSheet, onDismiss: { keyboardFocus = true }) { sheet in
            switch sheet {
            case .export: ExportSheet()
            case .settings: SettingsSheet()
            case .help: HelpSheet()
            }
        }
        .statusBarHidden(hidden)
        .persistentSystemOverlays(hidden ? .hidden : .automatic)
    }

    private var isEmpty: Bool { store.session.isEmpty && !store.scanning }

    private var showInfo: Bool {
        store.settings.infoPanelVisible && !store.chromeHidden && !isEmpty && sizeClass != .compact
    }

    @ViewBuilder private var content: some View {
        if store.scanning {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Lettura della cartella…").font(.footnote).foregroundStyle(Theme.muted)
            }
        } else if isEmpty {
            EmptyStateView()
        } else {
            switch store.viewMode {
            case .loupe: LoupeView()
            case .grid: GridPage()
            case .compare: CompareView()
            }
        }
    }

    private func updateScreenEdge(_ size: CGSize) {
        store.images.screenEdge = max(1024, Int(max(size.width, size.height) * displayScale))
    }

    // MARK: - Keyboard

    private func handle(_ press: KeyPress) -> Bool {
        guard store.activeSheet == nil else { return false }
        if press.modifiers.contains(.command) { return false }   // ⌘ shortcuts are menu commands
        let rows = store.viewMode == .grid ? store.gridColumns : 1
        switch press.key {
        case .rightArrow: store.next(); return true
        case .leftArrow: store.previous(); return true
        case .downArrow: store.step(rows); return true
        case .upArrow: store.step(-rows); return true
        case .home: store.first(); return true
        case .end: store.last(); return true
        case .return:
            if store.selecting { store.shareCurrentOrSelection() } else { store.viewMode = .loupe }
            return true
        case .space:
            if store.selecting, let uid = store.current?.uid { store.toggleSelected(uid) } else { toggleZoom() }
            return true
        case .escape:
            if store.selecting { store.endSelection() } else if store.chromeHidden { store.chromeHidden = false } else if store.viewMode != .loupe { store.viewMode = .loupe }
            return true
        case .tab:
            withAnimation(.easeInOut(duration: 0.2)) { store.chromeHidden.toggle() }
            return true
        default:
            break
        }
        let shift = press.modifiers.contains(.shift)
        switch press.characters.lowercased() {
        case "p": store.toggleFlag(1)
        case "x": store.toggleFlag(-1)
        case "u": store.setFlag(0)
        case "0", "1", "2", "3", "4", "5": store.setStars(Int(press.characters) ?? 0)
        case "6", "7", "8", "9": store.toggleLabel((Int(press.characters) ?? 5) - 5)
        case "r": store.rotate(shift ? -1 : 1)
        case "n": store.nextUnflagged()
        case "z": toggleZoom()
        case "+", "=": store.zoom(.zoomIn)
        case "-": store.zoom(.zoomOut)
        case "e": store.viewMode = .loupe
        case "g": store.viewMode = .grid
        case "c": store.viewMode = .compare
        case "i": withAnimation(.easeInOut(duration: 0.2)) { store.settings.infoPanelVisible.toggle() }
        case "b": store.cycleBackground()
        case "f": store.settings.filmstripVisible.toggle()
        case "a":
            store.setAutoAdvance(!store.settings.autoAdvance)
            store.showToast(store.settings.autoAdvance ? "Avanza dopo il voto" : "Resta sulla foto dopo il voto")
        case "h", "?": store.activeSheet = .help
        case "l": store.shareCurrentOrSelection()
        case "s":
            if store.selecting { store.endSelection() } else { store.beginSelection() }
        default: return false
        }
        return true
    }

    private func toggleZoom() {
        if store.viewMode == .grid { store.viewMode = .loupe } else { store.zoom(.toggle) }
    }
}

struct EmptyStateView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let none = store.session.totalCount == 0
        VStack(spacing: 14) {
            Text(none ? "In questa cartella non ci sono foto" : "Nessuna foto con questo filtro")
                .font(.title2)
                .foregroundStyle(Theme.text)
            Text(none ? "Cercate anche nelle sottocartelle. Formati: JPG, HEIC, PNG, TIFF e i RAW supportati da iPadOS."
                      : "Le foto ci sono, ma nessuna corrisponde al filtro scelto.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Button(none ? "Apri un'altra cartella…" : "Mostra tutte le foto") {
                if none { store.showFolderPicker = true } else { store.setFilter(.all) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

/// ⌘ shortcuts, shown in the iPad menu bar and in the ⌘-hold overlay.
struct PhotoSelCommands: Commands {
    let store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Apri cartella…") { store.showFolderPicker = true }
                .keyboardShortcut("o")
            Button("Rileggi la cartella") { store.reload() }
                .keyboardShortcut("r")
                .disabled(!store.hasFolder)
            Button("Chiudi cartella") { store.closeFolder() }
                .keyboardShortcut("w")
                .disabled(!store.hasFolder)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Annulla valutazione") { store.undo() }
                .keyboardShortcut("z")
                .disabled(!store.canUndo)
        }
        CommandMenu("Foto") {
            Button("Esporta…") { store.activeSheet = .export }
                .keyboardShortcut("e")
                .disabled(!store.hasFolder)
            Button("Impostazioni…") { store.activeSheet = .settings }
                .keyboardShortcut(",")
            Divider()
            ForEach(Array(PhotoFilter.allCases.enumerated()), id: \.offset) { i, f in
                Button("Filtro: \(f.title)") { store.setFilter(f) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
                    .disabled(!store.hasFolder)
            }
        }
    }
}
