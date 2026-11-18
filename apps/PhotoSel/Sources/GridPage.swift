import PhotoSelCore
import SwiftUI

/// Grid of all the visible photos. Tap selects, double tap opens the single view.
struct GridPage: View {
    @Environment(AppStore.self) private var store
    private let minTile: CGFloat = 180
    private let spacing: CGFloat = 10

    var body: some View {
        let session = store.session
        let currentUID = session.current?.uid
        VStack(spacing: 0) {
        SelectionBar()
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minTile), spacing: spacing)], spacing: spacing + 4) {
                        ForEach(session.visible, id: \.self) { uid in
                            if let photo = session.photo(uid: uid) {
                                if store.selecting {
                                    ThumbTile(photo: photo, isCurrent: uid == currentUID, selected: store.selection.contains(uid))
                                        .id(uid)
                                        .onTapGesture { store.toggleSelected(uid) }
                                } else {
                                    ThumbTile(photo: photo, isCurrent: uid == currentUID)
                                        .id(uid)
                                        .onTapGesture(count: 2) {
                                            store.select(uid: uid)
                                            store.viewMode = .loupe
                                        }
                                        .onTapGesture { store.select(uid: uid) }
                                        .contextMenu { RatingMenu(uid: uid) }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .onAppear {
                    updateColumns(geo.size.width)
                    if let currentUID { proxy.scrollTo(currentUID, anchor: .center) }
                }
                .onChange(of: geo.size.width) { _, w in updateColumns(w) }
                .onChange(of: currentUID) { _, uid in
                    guard let uid else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(uid) }
                }
            }
        }
        }
        .background(Theme.chrome)
    }

    private func updateColumns(_ width: CGFloat) {
        store.gridColumns = max(1, Int((width - 24 + spacing) / (minTile + spacing)))
    }
}

/// Above the grid: enter selection mode, select all / kept, send to Lightroom.
struct SelectionBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            if store.selecting {
                Text(store.selection.isEmpty ? "Tocca le foto da scegliere" : "\(store.selection.count) selezionate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Tutte") { store.selectAllVisible() }
                Button("Tenute") { store.selectPicksVisible() }
                    .disabled(store.counts.picks == 0)
                Button("Nessuna") { store.clearSelection() }
                    .disabled(store.selection.isEmpty)
                formatMenu
                Button {
                    store.share(store.selectedPhotos)
                } label: {
                    Label("Apri in Lightroom…", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selection.isEmpty)
                Button("Fine") { store.endSelection() }
                    .fontWeight(.semibold)
            } else {
                Spacer()
                formatMenu
                Button {
                    store.beginSelection()
                } label: {
                    Label("Seleziona", systemImage: "checkmark.circle")
                }
            }
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(Theme.chrome)
    }

    private var formatMenu: some View {
        Menu {
            Picker("File da inviare", selection: Bindable(store).settings.shareFormat) {
                ForEach(ShareFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } label: {
            Label(store.settings.shareFormat.title, systemImage: "doc.on.doc")
        }
        .help("Quale file di ogni foto inviare")
    }
}

/// Long-press menu on a thumbnail: rate without opening the photo.
struct RatingMenu: View {
    @Environment(AppStore.self) private var store
    let uid: Int

    var body: some View {
        Button { rate { store.toggleFlag(1) } } label: { Label("Tieni", systemImage: "checkmark.circle") }
        Button { rate { store.toggleFlag(-1) } } label: { Label("Scarta", systemImage: "xmark.circle") }
        Menu("Stelle") {
            ForEach(0...5, id: \.self) { n in
                Button(n == 0 ? "Nessuna" : String(repeating: "★", count: n)) { rate { store.setStars(n) } }
            }
        }
        Menu("Etichetta") {
            ForEach(0...5, id: \.self) { n in
                Button(Theme.labelNames[n]) { rate { store.setLabel(n) } }
            }
        }
        Divider()
        Button {
            if let p = store.session.photo(uid: uid) { store.share([p]) }
        } label: { Label("Apri in Lightroom…", systemImage: "square.and.arrow.up") }
        Button { store.select(uid: uid); store.beginSelection() } label: {
            Label("Seleziona più foto", systemImage: "checkmark.circle")
        }
    }

    /// Rates the long-pressed photo even with "advance after rating" on.
    private func rate(_ action: () -> Void) {
        store.select(uid: uid)
        let advance = store.session.autoAdvance
        store.setAutoAdvance(false)
        action()
        store.setAutoAdvance(advance)
    }
}
