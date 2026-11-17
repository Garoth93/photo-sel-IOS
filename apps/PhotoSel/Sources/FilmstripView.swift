import PhotoSelCore
import SwiftUI

/// Filmstrip at the bottom: shots of the same burst are joined by a line.
struct FilmstripView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let session = store.session
        let currentUID = session.current?.uid
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(session.visible, id: \.self) { uid in
                        if let photo = session.photo(uid: uid) {
                            VStack(spacing: 3) {
                                ThumbTile(photo: photo, isCurrent: uid == currentUID, compact: true)
                                burstLine(photo)
                            }
                            .frame(width: 112)
                            .id(uid)
                            .onTapGesture { store.select(uid: uid) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onAppear { if let currentUID { proxy.scrollTo(currentUID, anchor: .center) } }
            .onChange(of: currentUID) { _, uid in
                guard let uid else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(uid, anchor: .center) }
            }
        }
        .frame(height: 118)
        .background(Theme.chrome)
    }

    @ViewBuilder private func burstLine(_ p: Photo) -> some View {
        if p.isBurst {
            Rectangle()
                .fill(Theme.muted.opacity(0.7))
                .frame(height: 2)
                .padding(.leading, p.burstIndex == 0 ? 4 : -3)
                .padding(.trailing, p.burstIndex == p.burstSize - 1 ? 4 : -3)
        } else {
            Color.clear.frame(height: 2)
        }
    }
}
