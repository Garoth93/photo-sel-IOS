import PhotoSelCore
import SwiftUI

/// Start screen: open a folder (Files, SD card reader, external drive) or a recent one.
struct WelcomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("photoSel")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("Scorri gli scatti, tieni i migliori, esporta solo quelli nel formato che ti serve.")
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                }

                Button { store.showFolderPicker = true } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus").font(.system(size: 34))
                        Text("Apri cartella…").font(.title3.weight(.semibold))
                        Text("Da File: iPad, iCloud Drive, scheda SD, disco esterno").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(.plain)

                if !store.settings.recents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aperte di recente").font(.headline).foregroundStyle(Theme.text)
                        VStack(spacing: 0) {
                            ForEach(store.settings.recents) { r in
                                Button { store.openRecent(r) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder").foregroundStyle(Theme.muted)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(r.name).foregroundStyle(Theme.text)
                                            Text(r.parentName).font(.caption).foregroundStyle(Theme.faint)
                                        }
                                        Spacer()
                                        Text(r.opened, format: .dateTime.day().month().hour().minute())
                                            .font(.caption).foregroundStyle(Theme.faint)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 54)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { store.forgetRecent(r) } label: {
                                        Label("Togli dall'elenco", systemImage: "minus.circle")
                                    }
                                }
                                if r.id != store.settings.recents.last?.id {
                                    Divider().overlay(Theme.line).padding(.leading, 44)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Come funziona").font(.headline).foregroundStyle(Theme.text)
                    tip("sdcard", "Collega il lettore di schede o la fotocamera all'iPad, poi in File scegli la cartella DCIM/… con le foto.")
                    tip("star", "Valuta con i pulsanti in basso o con la tastiera: P tieni, X scarta, 1–5 stelle, 6–9 etichette.")
                    tip("square.split.2x1", "Le raffiche sono raggruppate: nel confronto ◆ indica la più nitida e lo zoom è sincronizzato.")
                    tip("doc.badge.gearshape", "Le valutazioni sono salvate in file .xmp accanto alle foto: Lightroom e Bridge le leggono.")
                    tip("square.and.arrow.up", "Alla fine esporta solo le foto scelte, nei formati che vuoi, anche nella libreria Foto.")
                }
            }
            .frame(maxWidth: 640)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.chrome)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
            Text(text).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ToastView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack {
            if let toast = store.toast {
                Text(toast.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.raised))
                    .overlay(Capsule().strokeBorder(Theme.line))
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    .padding(.bottom, 190)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id(toast.id)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .allowsHitTesting(false)
    }
}
