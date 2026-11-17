import PhotoSelCore
import SwiftUI

/// Bottom bar for touch: navigation, keep/reject, stars, labels, rotation.
struct RatingBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let session = store.session
        let p = store.current
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    IconButton(systemImage: "chevron.left", help: "Precedente (←)") { store.previous() }
                    IconButton(systemImage: "chevron.right", help: "Successiva (→)") { store.next() }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.count > 0 ? "\(session.currentRow + 1) di \(session.count)" : "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                    Text(p?.displayFileName ?? "")
                        .font(.caption2)
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
                .frame(width: 110, alignment: .leading)

                divider
                pill("Scarta", "xmark", Theme.reject, on: p?.flag == -1) { store.toggleFlag(-1) }
                pill("Tieni", "checkmark", Theme.keep, on: p?.flag == 1) { store.toggleFlag(1) }
                divider
                StarRow(stars: p?.stars ?? 0, size: 24) { n in store.setStars(n == p?.stars ? 0 : n) }
                divider
                LabelDots(selected: p?.label ?? 0, size: 18) { store.toggleLabel($0) }
                divider
                IconButton(systemImage: "rotate.right", help: "Ruota (R)") { store.rotate(1) }
                Button { store.nextUnflagged() } label: {
                    Label("Da valutare", systemImage: "forward.end")
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .foregroundStyle(Theme.text)
                        .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
                .help("Prossima da valutare (N)")
                Button {
                    store.setAutoAdvance(!store.settings.autoAdvance)
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(store.settings.autoAdvance ? Theme.accent : Theme.faint).frame(width: 7, height: 7)
                        Text(store.settings.autoAdvance ? "Avanza dopo il voto" : "Resta sulla foto")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                }
                .buttonStyle(.plain)
                .help("Avanza dopo il voto (A)")
            }
            .padding(.horizontal, 10)
            .disabled(p == nil)
        }
        .frame(height: 54)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(width: 1, height: 26)
    }

    private func pill(_ title: String, _ icon: String, _ tint: Color, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .foregroundStyle(on ? Color.white : tint)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? tint : tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
