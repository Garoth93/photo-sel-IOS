import PhotoSelCore
import SwiftUI
import UniformTypeIdentifiers

/// Export once at the end: which photos, which formats, where, copy or move.
struct ExportSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var o = ExportOptions()
    @State private var customDestination: URL?
    @State private var pickingDestination = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if store.exporting {
                    progressView
                } else if let message = store.exportMessage {
                    resultView(message)
                } else {
                    form
                }
            }
            .navigationTitle("Esporta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(store.exporting)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            store.clearExportMessage()
            o = store.defaultExportOptions()
        }
        .fileImporter(isPresented: $pickingDestination, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { customDestination = url }
        }
    }

    private var photoCount: Int { store.exportCount(o.selection, minStars: o.minStars) }
    private var formatsNoXmp: [String] { o.formats.filter { $0 != FileKinds.sidecar } }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if store.exporting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Interrompi", role: .destructive) { store.cancelExport() }
            }
        } else if store.exportMessage != nil {
            ToolbarItem(placement: .cancellationAction) {
                Button("Torna alle opzioni") { store.clearExportMessage() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Chiudi") { dismiss() }
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annulla") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(o.move ? "Sposta \(photoCount)" : "Esporta \(photoCount)") {
                    store.startExport(o, destination: customDestination)
                }
                .disabled(formatsNoXmp.isEmpty && !o.moveRejects)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var form: some View {
        Form {
            Section("Quali foto") {
                Picker("Quali foto", selection: $o.selection) {
                    Text("Le tenute (\(store.exportCount(.picks, minStars: o.minStars)))").tag(ExportSelection.picks)
                    Text("Con almeno \(o.minStars) \(o.minStars == 1 ? "stella" : "stelle") (\(store.exportCount(.stars, minStars: o.minStars)))")
                        .tag(ExportSelection.stars)
                    Text("Tutte tranne le scartate (\(store.exportCount(.notRejected, minStars: o.minStars)))")
                        .tag(ExportSelection.notRejected)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if o.selection == .stars {
                    Stepper("Stelle minime: \(String(repeating: "★", count: o.minStars))", value: $o.minStars, in: 1...5)
                }
            }

            Section {
                ForEach(store.extensions, id: \.self) { ext in
                    Toggle(FileKinds.label(ext), isOn: Binding(
                        get: { o.formats.contains(ext) },
                        set: { on in
                            if on { if !o.formats.contains(ext) { o.formats.append(ext) } } else { o.formats.removeAll { $0 == ext } }
                        }))
                }
            } header: {
                Text("In quali formati")
            } footer: {
                if formatsNoXmp.isEmpty {
                    Text("Scegli almeno un formato.").foregroundStyle(Theme.reject)
                }
            }

            Section {
                if let customDestination {
                    LabeledContent("Cartella", value: customDestination.lastPathComponent)
                    Button("Usa una sottocartella di \(store.folderName)") { self.customDestination = nil }
                } else {
                    LabeledContent("Sottocartella di \(store.folderName)") {
                        TextField("selezionate", text: $o.subfolder)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Button("Scegli un'altra cartella…") { pickingDestination = true }
                Toggle("Una sottocartella per formato (\((formatsNoXmp.isEmpty ? ["jpg"] : formatsNoXmp).map { $0 + "/" }.joined(separator: ", ")))",
                       isOn: $o.perFormatFolder)
                Picker("Operazione", selection: $o.move) {
                    Text("Copia").tag(false)
                    Text("Sposta").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Aggiungi anche alla libreria Foto", isOn: $o.saveToPhotos)
            } header: {
                Text("Dove")
            } footer: {
                Text(o.move
                     ? "I file escono dalla cartella delle foto. Se in destinazione esiste già un file con lo stesso nome, viene aggiunto un numero."
                     : "Gli originali restano dove sono. Se in destinazione esiste già un file con lo stesso nome, viene aggiunto un numero.")
            }

            let rejects = store.counts.rejects
            if rejects > 0 {
                Section {
                    Toggle(rejects == 1 ? "Sposta anche la foto scartata in una sottocartella"
                                        : "Sposta anche le \(rejects) scartate in una sottocartella",
                           isOn: $o.moveRejects)
                    if o.moveRejects {
                        LabeledContent("dentro \(store.folderName)") {
                            TextField("da_eliminare", text: $o.rejectFolder)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text("Scartate")
                }
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 16) {
            let p = store.exportProgress
            ProgressView(value: Double(p?.done ?? 0), total: Double(max(p?.total ?? 1, 1)))
                .frame(maxWidth: 420)
            Text(p.map { $0.total > 0 ? "File \(min($0.done + 1, $0.total)) di \($0.total)" : "Preparazione…" } ?? "Preparazione…")
                .font(.headline)
            Text(p?.fileName ?? "").font(.footnote).foregroundStyle(Theme.muted)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: store.exportSucceeded ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(store.exportSucceeded ? Theme.keep : Theme.reject)
            Text(message).font(.headline).multilineTextAlignment(.center)
            if store.exportSucceeded {
                Text("Destinazione: " + (customDestination?.lastPathComponent ?? "\(store.folderName)/\(o.subfolder)"))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
