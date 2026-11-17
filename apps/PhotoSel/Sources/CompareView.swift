import PhotoSelCore
import SwiftUI

/// Burst comparison: 2–4 photos side by side with synchronised zoom.
/// Double tap on the subject's eye and scroll: every pane follows.
struct CompareView: View {
    @Environment(AppStore.self) private var store
    @State private var sync = ZoomSync()

    var body: some View {
        let session = store.session
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let cur = session.current, cur.isBurst {
                    Text("Raffica di \(cur.burstSize) scatti · ◆ la più nitida")
                } else {
                    Text("Foto vicine")
                }
                Spacer()
                Text("Affiancate").foregroundStyle(Theme.muted)
                Picker("Affiancate", selection: Binding(get: { session.compareSize }, set: { store.setCompareSize($0) })) {
                    ForEach(2...4, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            .font(.footnote)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            HStack(spacing: 3) {
                ForEach(session.compareRows.compactMap { session.uid(atRow: $0) }, id: \.self) { uid in
                    if let photo = session.photo(uid: uid) {
                        pane(photo, isCurrent: uid == session.current?.uid)
                    }
                }
            }
        }
        .background(Theme.chrome)
    }

    private func pane(_ photo: Photo, isCurrent: Bool) -> some View {
        PhotoPane(photo: photo,
                  sync: sync,
                  zoomRequest: isCurrent ? store.zoomRequest : nil,
                  onTap: { store.select(uid: photo.uid) })
            .overlay {
                Rectangle().strokeBorder(isCurrent ? Theme.accent : Color.clear, lineWidth: 3)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) { caption(photo).allowsHitTesting(false) }
    }

    private func caption(_ p: Photo) -> some View {
        let session = store.session
        let best = session.isBurstBest(uid: p.uid)
        let value = p.isBurst ? session.burstSharpness(uid: p.uid) : session.sharpness(uid: p.uid)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(p.baseName).font(.footnote.weight(.semibold))
                if p.flag != 0 {
                    Text(p.flag == 1 ? "✓ Tenuta" : "✕ Scartata")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(p.flag == 1 ? Theme.keep : Theme.reject)
                }
                if p.stars > 0 {
                    Text(String(repeating: "★", count: p.stars)).font(.caption).foregroundStyle(Theme.accent)
                }
                if p.label > 0 {
                    Circle().fill(Theme.labelColors[p.label]).frame(width: 9, height: 9)
                }
                Spacer()
            }
            if p.analyzed {
                HStack(spacing: 6) {
                    SharpnessBar(value: value, highlight: best)
                    Text(best ? "◆ la più nitida" : "nitidezza")
                        .font(.caption2)
                        .foregroundStyle(best ? Theme.accent : Theme.muted)
                }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(8)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
    }
}

struct SharpnessBar: View {
    let value: Double
    var highlight = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(highlight ? Theme.accent : Theme.muted)
                    .frame(width: max(3, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}
