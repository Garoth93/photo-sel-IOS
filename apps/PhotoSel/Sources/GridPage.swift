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
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: minTile), spacing: spacing)], spacing: spacing + 4) {
                        ForEach(session.visible, id: \.self) { uid in
                            if let photo = session.photo(uid: uid) {
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
        .background(Theme.chrome)
    }

    private func updateColumns(_ width: CGFloat) {
        store.gridColumns = max(1, Int((width - 24 + spacing) / (minTile + spacing)))
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
