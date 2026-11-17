import PhotoSelCore
import SwiftUI

/// Folder menu, view modes and actions; below, the filter chips.
struct TopBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                folderMenu
                Spacer(minLength: 8)
                viewModes
                Spacer().frame(width: 6)
                IconButton(systemImage: "arrow.uturn.backward", help: "Annulla ultima valutazione (⌘Z)") { store.undo() }
                    .disabled(!store.canUndo)
                    .opacity(store.canUndo ? 1 : 0.4)
                IconButton(systemImage: "sidebar.right", help: "Pannello informazioni (I)", active: store.settings.infoPanelVisible) {
                    withAnimation(.easeInOut(duration: 0.2)) { store.settings.infoPanelVisible.toggle() }
                }
                IconButton(systemImage: "slider.horizontal.3", help: "Impostazioni (⌘,)") { store.activeSheet = .settings }
                IconButton(systemImage: "keyboard", help: "Scorciatoie e gesti (H)") { store.activeSheet = .help }
                Button {
                    store.activeSheet = .export
                } label: {
                    Text(store.counts.picks > 0 ? "Esporta \(store.counts.picks)" : "Esporta…")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .foregroundStyle(Theme.accentInk)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)

            FilterBar()
        }
        .background(Theme.chrome)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var folderMenu: some View {
        Menu {
            Button { store.showFolderPicker = true } label: { Label("Apri cartella…", systemImage: "folder") }
            Button { store.reload() } label: { Label("Rileggi la cartella", systemImage: "arrow.clockwise") }
            let others = store.settings.recents.filter { $0.path != store.folder?.path }
            if !others.isEmpty {
                Section("Aperte di recente") {
                    ForEach(others) { r in
                        Button { store.openRecent(r) } label: { Text(r.name); Text(r.parentName) }
                    }
                }
            }
            Divider()
            Button(role: .destructive) { store.closeFolder() } label: { Label("Chiudi cartella", systemImage: "xmark") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Theme.muted)
                Text(store.folderName)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var viewModes: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                IconButton(systemImage: mode.systemImage, help: "\(mode.title) (\(mode.key))", active: store.viewMode == mode) {
                    store.viewMode = mode
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
    }
}

struct FilterBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(PhotoFilter.allCases, id: \.self) { f in
                        FilterChip(title: f.title, count: store.counts.count(for: f), dot: dot(f),
                                   selected: store.session.filter == f) { store.setFilter(f) }
                    }
                }
                .padding(.horizontal, 10)
            }
            if store.analyzing {
                HStack(spacing: 6) {
                    ProgressView(value: Double(store.analysisDone), total: Double(max(store.analysisTotal, 1)))
                        .frame(width: 70)
                    Text("Nitidezza \(store.analysisDone)/\(store.analysisTotal)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
                .padding(.trailing, 12)
            } else if !store.settings.writeXmp {
                Label("Valutazioni non salvate su disco", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(Theme.reject)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 38)
    }

    private func dot(_ f: PhotoFilter) -> Color? {
        switch f {
        case .picks: return Theme.keep
        case .rejects: return Theme.reject
        default: return nil
        }
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    var dot: Color?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(title).font(.subheadline)
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(selected ? Theme.accentInk.opacity(0.6) : Theme.faint)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .foregroundStyle(selected ? Theme.accentInk : Theme.text)
            .background(Capsule().fill(selected ? Theme.text : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
