import PhotoSelCore
import SwiftUI

/// Thumbnail loaded in the background (disk cache), rotated for the session.
struct ThumbImage: View {
    @Environment(AppStore.self) private var store
    let url: URL
    var rotation = 0

    private struct Loaded { let url: URL; let image: UIImage }
    @State private var loaded: Loaded?

    var body: some View {
        let image = loaded?.url == url ? loaded?.image : store.images.cachedThumbnail(url)
        ZStack {
            if let image {
                Image(uiImage: image.rotated(rotation))
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().controlSize(.small).tint(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            if loaded?.url == url { return }
            if let img = await store.images.thumbnail(url) {
                loaded = Loaded(url: url, image: img)
            }
        }
    }
}

/// Grid / filmstrip tile: flag, stars, colour label, sharpest of the burst (◆).
struct ThumbTile: View {
    @Environment(AppStore.self) private var store
    let photo: Photo
    let isCurrent: Bool
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Theme.panel)
                if let url = photo.displayURL {
                    ThumbImage(url: url, rotation: photo.rotation)
                        .padding(compact ? 3 : 6)
                        .opacity(photo.flag == -1 ? 0.4 : 1)
                }
            }
            .overlay(alignment: .topLeading) { flagBadge.padding(5) }
            .overlay(alignment: .topTrailing) { labelDot.padding(6) }
            .overlay(alignment: .bottomLeading) { starsBadge.padding(5) }
            .overlay(alignment: .bottomTrailing) {
                if store.session.isBurstBest(uid: photo.uid) {
                    Text("◆").font(.system(size: compact ? 10 : 13)).foregroundStyle(Theme.accent).padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCurrent ? Theme.accent : Color.clear, lineWidth: compact ? 2.5 : 3)
            }
            .aspectRatio(compact ? 1.45 : 1.3, contentMode: .fit)

            if compact {
                Text(photo.isBurst && photo.burstIndex == 0 ? "\(photo.baseName)  ×\(photo.burstSize)" : photo.baseName)
                    .font(.system(size: 10))
                    .foregroundStyle(isCurrent ? Theme.text : Theme.faint)
                    .lineLimit(1)
            } else {
                HStack(spacing: 6) {
                    Text(photo.baseName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(photo.extensionBadges.joined(separator: " "))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
                Text(photo.exif.summaryLine.isEmpty ? " " : photo.exif.summaryLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var flagBadge: some View {
        if photo.flag != 0 {
            Image(systemName: photo.flag == 1 ? "checkmark" : "xmark")
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
                .background(Circle().fill(photo.flag == 1 ? Theme.keep : Theme.reject))
        }
    }

    @ViewBuilder private var labelDot: some View {
        if photo.label > 0 {
            Circle()
                .fill(Theme.labelColors[photo.label])
                .frame(width: compact ? 9 : 12, height: compact ? 9 : 12)
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
        }
    }

    @ViewBuilder private var starsBadge: some View {
        if photo.stars > 0 {
            Text(String(repeating: "★", count: photo.stars))
                .font(.system(size: compact ? 9 : 11))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.65)))
        }
    }
}
