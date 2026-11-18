import PhotoSelCore
import SwiftUI

struct SettingsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var gap: Double = 1000
    @State private var cacheText = ""

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Quando ci sono sia JPG sia RAW, mostra") {
                    Picker("Mostra", selection: Binding(get: { store.settings.preferRaw }, set: { store.setPreferRaw($0) })) {
                        Text("Il JPG").tag(false)
                        Text("L'anteprima del RAW").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Sfondo del visualizzatore") {
                    Picker("Sfondo", selection: $store.settings.loupeBackground) {
                        ForEach(0..<3, id: \.self) { i in Text(AppSettings.loupeBackgroundNames[i]).tag(i) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Valutazione") {
                    Toggle("Passa alla foto successiva dopo il voto",
                           isOn: Binding(get: { store.settings.autoAdvance }, set: { store.setAutoAdvance($0) }))
                    Toggle("Salva le valutazioni in file .xmp", isOn: $store.settings.writeXmp)
                }

                Section {
                    Slider(value: $gap, in: 200...5000, step: 100, onEditingChanged: { editing in
                        if !editing { store.setBurstGap(Int(gap)) }
                    })
                    Text(gapText).font(.footnote).foregroundStyle(Theme.muted)
                } header: {
                    Text("Raffiche")
                }

                Section("Confronto") {
                    Picker("Foto affiancate", selection: Binding(get: { store.settings.compareSize }, set: { store.setCompareSize($0) })) {
                        ForEach(2...4, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Mostra la pellicola (F)", isOn: $store.settings.filmstripVisible)
                }

                Section("Miniature") {
                    LabeledContent("Cache su disco", value: cacheText)
                    Button("Svuota la cache") {
                        store.clearThumbnailCache()
                        cacheText = store.cacheSizeText
                    }
                }

                Section {
                    LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fatto") { dismiss() } }
            }
        }
        .onAppear {
            gap = Double(store.settings.burstGapMs)
            cacheText = store.cacheSizeText
        }
    }

    private var gapText: String {
        var s = AppSettings()
        s.burstGapMs = Int(gap)
        return s.burstGapText
    }
}

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let keys: [(String, String)] = [
        ("P / X / U", "Tieni / Scarta / Togli"),
        ("1–5, 0", "Stelle / togli stelle"),
        ("6 7 8 9", "Etichette rosso, giallo, verde, blu"),
        ("← →", "Foto precedente / successiva"),
        ("↑ ↓", "Riga sopra / sotto nella griglia"),
        ("N", "Prossima da valutare"),
        ("E  G  C", "Singola / Griglia / Confronto"),
        ("Z, Spazio", "Adatta ↔ 100%"),
        ("+ / −", "Ingrandisci / riduci"),
        ("R / Maiusc+R", "Ruota la visualizzazione"),
        ("A", "Avanza dopo il voto"),
        ("I", "Pannello informazioni"),
        ("F", "Pellicola"),
        ("B", "Sfondo del visualizzatore"),
        ("Tab", "Solo la foto"),
        ("Esc", "Torna alla vista singola"),
        ("L", "Apri in Lightroom (foto corrente o selezione)"),
        ("S", "Selezione multipla nella griglia"),
        ("Spazio (selezione)", "Seleziona / deseleziona la foto corrente"),
        ("⌘Z", "Annulla"),
        ("⌘1…5", "Filtri"),
        ("⌘E", "Esporta"),
        ("⌘O", "Apri cartella"),
        ("⌘R", "Rileggi la cartella"),
    ]

    private let gestures: [(String, String)] = [
        ("Scorri a sinistra / destra", "Foto successiva / precedente"),
        ("Doppio tocco", "Adatta ↔ 100% nel punto toccato"),
        ("Pizzica", "Zoom libero"),
        ("Tocco sulla foto", "Solo la foto (nasconde le barre)"),
        ("Confronto: tocco su un riquadro", "Lo rende la foto corrente"),
        ("Griglia: doppio tocco", "Apre la foto"),
        ("Griglia: tocco prolungato", "Valuta senza aprire"),
        ("Tocco sulla stella già scelta", "Toglie le stelle"),
        ("Griglia: Seleziona", "Scegli più foto e aprile in Lightroom"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Tastiera") {
                    ForEach(keys, id: \.0) { row($0.0, $0.1) }
                }
                Section("Gesti") {
                    ForEach(gestures, id: \.0) { row($0.0, $0.1) }
                }
            }
            .navigationTitle("Scorciatoie e gesti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fatto") { dismiss() } }
            }
        }
    }

    private func row(_ key: String, _ action: String) -> some View {
        HStack {
            Text(key).font(.body.monospaced()).foregroundStyle(Theme.accent)
            Spacer()
            Text(action).foregroundStyle(Theme.text)
        }
    }
}
