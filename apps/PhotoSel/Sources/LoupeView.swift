import PhotoSelCore
import SwiftUI

/// Single photo: screen-size image at once, full resolution when zoomed in.
struct PhotoPane: View {
    @Environment(AppStore.self) private var store
    let photo: Photo
    var sync: ZoomSync?
    var zoomRequest: ZoomRequest?
    var swipeEnabled = false
    var onSwipe: ((Int) -> Void)?
    var onTap: (() -> Void)?

    private struct Loaded { let url: URL; let image: UIImage }
    @State private var screen: Loaded?
    @State private var full: Loaded?
    @State private var wantsFull = false
    @State private var loadingFull = false

    var body: some View {
        let url = photo.displayURL
        let base: UIImage? = {
            guard let url else { return nil }
            if let full, full.url == url { return full.image }
            if let screen, screen.url == url { return screen.image }
            return store.images.cachedScreen(url) ?? store.images.cachedThumbnail(url)
        }()
        ZoomableImageView(
            image: base?.rotated(photo.rotation),
            identity: photo.uid * 4 + photo.rotation / 90,
            background: UIColor(Theme.loupeBackground(store.settings.loupeBackground)),
            zoomRequest: zoomRequest,
            sync: sync,
            swipeEnabled: swipeEnabled,
            onSwipe: onSwipe,
            onSingleTap: onTap,
            onZoomedIn: { zoomed in if zoomed { wantsFull = true } }
        )
        .overlay(alignment: .topTrailing) {
            if loadingFull {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("100%…").font(.caption2)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(8)
            }
        }
        .task(id: url) {
            wantsFull = false
            guard let url else { return }
            if screen?.url == url { return }
            if let img = await store.images.screen(url) { screen = Loaded(url: url, image: img) }
        }
        .task(id: wantsFull ? url : nil) {
            guard wantsFull, let url, full?.url != url else { return }
            loadingFull = true
            if let img = await store.images.full(url) { full = Loaded(url: url, image: img) }
            loadingFull = false
        }
    }
}

struct LoupeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let photo = store.current {
            PhotoPane(photo: photo,
                      zoomRequest: store.zoomRequest,
                      swipeEnabled: true,
                      onSwipe: { $0 > 0 ? store.next() : store.previous() },
                      onTap: { withAnimation(.easeInOut(duration: 0.2)) { store.chromeHidden.toggle() } })
                .ignoresSafeArea(edges: store.chromeHidden ? .all : [])
                .overlay(alignment: .bottomLeading) {
                    if !photo.exif.summaryLine.isEmpty && !store.chromeHidden {
                        Text(photo.exif.summaryLine)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}
