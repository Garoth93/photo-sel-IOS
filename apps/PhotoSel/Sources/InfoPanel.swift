import PhotoSelCore
import SwiftUI

/// Right panel: file, rating, histogram, sharpness, shooting data.
struct InfoPanel: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            if let p = store.current {
                VStack(alignment: .leading, spacing: 18) {
                    header(p)
                    RatingControls(photo: p)
                    Divider().overlay(Theme.line)
                    section("Istogramma") {
                        if p.analyzed {
                            HistogramView(values: p.histogram)
                                .frame(height: 92)
                        } else {
                            Text("In calcolo…").font(.footnote).foregroundStyle(Theme.faint)
                                .frame(maxWidth: .infinity, minHeight: 92)
                                .background(Theme.panel)
                        }
                    }
                    section("Nitidezza") { sharpness(p) }
                    Divider().overlay(Theme.line)
                    section("Scatto") { shooting(p) }
                    actions(p)
                }
                .padding(16)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.chrome)
    }

    private func header(_ p: Photo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(p.baseName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                ForEach(p.extensionBadges, id: \.self) { ext in
                    Text(ext)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line))
                }
                Text(ItalianFormat.dataSize(p.totalBytes))
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    @ViewBuilder private func sharpness(_ p: Photo) -> some View {
        let session = store.session
        if !p.analyzed {
            Text("In calcolo…").font(.footnote).foregroundStyle(Theme.faint)
        } else if p.isBurst {
            let best = session.isBurstBest(uid: p.uid)
            SharpnessBar(value: session.burstSharpness(uid: p.uid), highlight: best)
            Text(best ? "◆ La più nitida della raffica (\(p.burstIndex + 1) di \(p.burstSize))"
                      : "Rispetto alla più nitida della raffica (\(p.burstIndex + 1) di \(p.burstSize))")
                .font(.footnote).foregroundStyle(best ? Theme.accent : Theme.muted)
        } else {
            SharpnessBar(value: session.sharpness(uid: p.uid))
            Text("Rispetto alle altre foto della cartella").font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private func shooting(_ p: Photo) -> some View {
        let e = p.exif
        if e.exposure > 0 || e.fnumber > 0 || e.iso > 0 {
            HStack(alignment: .top, spacing: 18) {
                bigValue(e.exposureText, "tempo")
                bigValue(e.apertureText, "diaframma")
                bigValue(e.iso > 0 ? "\(e.iso)" : "", "ISO")
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            row("Focale", e.focalText)
            row("Obiettivo", e.lens)
            row("Fotocamera", e.cameraText)
            row("Data", e.captured.map { Self.dateFormatter.string(from: $0) } ?? "")
            row("Dimensioni", p.dimensionsText)
            row(p.directories.count > 1 ? "Cartelle" : "Cartella", store.folderText(p))
        }
    }

    private func bigValue(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.isEmpty ? "–" : value).font(.title3.monospacedDigit()).foregroundStyle(Theme.text)
            Text(label).font(.caption2).foregroundStyle(Theme.faint)
        }
    }

    @ViewBuilder private func row(_ key: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(key).font(.footnote).foregroundStyle(Theme.faint).frame(width: 82, alignment: .leading)
                Text(value).font(.footnote).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actions(_ p: Photo) -> some View {
        HStack(spacing: 4) {
            IconButton(systemImage: "rotate.left", help: "Ruota a sinistra (Maiusc+R)") { store.rotate(-1) }
            IconButton(systemImage: "rotate.right", help: "Ruota a destra (R)") { store.rotate(1) }
            if let url = p.displayURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 40, height: 36)
                }
                .foregroundStyle(Theme.muted)
            }
        }
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateFormat = "d MMM yyyy, HH:mm:ss"
        return f
    }()
}

/// Keep / reject, stars, colour labels for the current photo.
struct RatingControls: View {
    @Environment(AppStore.self) private var store
    let photo: Photo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FlagButton(title: "Tieni", key: "P", tint: Theme.keep, on: photo.flag == 1) { store.toggleFlag(1) }
                FlagButton(title: "Scarta", key: "X", tint: Theme.reject, on: photo.flag == -1) { store.toggleFlag(-1) }
            }
            StarRow(stars: photo.stars, size: 22) { store.setStars($0 == photo.stars ? 0 : $0) }
            LabelDots(selected: photo.label, size: 20) { store.toggleLabel($0) }
        }
    }
}

struct FlagButton: View {
    let title: String
    let key: String
    let tint: Color
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text((on ? "✓ " : "") + title).font(.subheadline.weight(on ? .semibold : .regular))
                Spacer()
                Text(key).font(.caption2).foregroundStyle(on ? tint.opacity(0.8) : Theme.faint)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? tint : Theme.text)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? tint.opacity(0.16) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? tint : Theme.line))
        }
        .buttonStyle(.plain)
    }
}

struct StarRow: View {
    let stars: Int
    var size: CGFloat = 20
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: size * 0.25) {
            ForEach(1...5, id: \.self) { n in
                Button { action(n) } label: {
                    Image(systemName: n <= stars ? "star.fill" : "star")
                        .font(.system(size: size * 0.8))
                        .foregroundStyle(n <= stars ? Theme.accent : Theme.faint)
                        .frame(width: size + 6, height: size + 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(n) stelle")
            }
        }
    }
}

struct LabelDots: View {
    let selected: Int
    var size: CGFloat = 18
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(1...5, id: \.self) { n in
                Button { action(n) } label: {
                    Circle()
                        .fill(Theme.labelColors[n].opacity(selected == n ? 1 : 0.55))
                        .frame(width: size, height: size)
                        .overlay(Circle().strokeBorder(selected == n ? Theme.text : Color.clear, lineWidth: 2))
                        .frame(width: size + 10, height: size + 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Etichetta \(Theme.labelNames[n])")
            }
        }
    }
}

struct IconButton: View {
    let systemImage: String
    var help: String = ""
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .frame(width: 40, height: 36)
                .foregroundStyle(active ? Theme.text : Theme.muted)
                .background(RoundedRectangle(cornerRadius: 7).fill(active ? Theme.raised : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// RGB histogram plus luminance (64 bins per channel).
struct HistogramView: View {
    let values: [Float]

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.panel))
            for i in 1..<4 {
                let x = size.width * CGFloat(i) / 4
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(Theme.line.opacity(0.6)), lineWidth: 0.5)
            }
            let bins = ImageAnalysis.histogramBins
            guard values.count >= 4 * bins else { return }
            let colors: [Color] = [Color.white.opacity(0.35), Color(hex: 0xe2625a).opacity(0.55),
                                   Color(hex: 0x5fbf87).opacity(0.55), Color(hex: 0x4f93e0).opacity(0.55)]
            for ch in [1, 2, 3, 0] {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for i in 0..<bins {
                    let x = size.width * CGFloat(i) / CGFloat(bins - 1)
                    let y = size.height * (1 - CGFloat(values[ch * bins + i]))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .color(colors[ch]))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
