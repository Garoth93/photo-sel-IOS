# CLAUDE.md — regole di lavoro per questa repo

Repo dell'app iPad **nativa (Swift + SwiftUI)** photoSel, sviluppate senza Mac:
il codice viene scritto su Linux (Claude Code) e compilato **solo** su GitHub
Actions con runner macOS. Le app non vanno su App Store: l'utente scarica il
`.ipa` non firmato dagli artifact e lo firma con Sideloadly/SideStore.

## Vincoli fissi

- Nativo vero: Swift/SwiftUI. Niente WebView che incapsula una PWA, niente
  framework cross-platform, salvo richiesta esplicita dell'utente.
- Nessun `.xcodeproj` committato: il progetto è generato in CI da
  `apps/<app>/project.yml` con XcodeGen. `.gitignore` lo esclude.
- La repo è **pubblica**: mai committare segreti, chiavi API, certificati,
  profili di provisioning, dati personali, Team ID reali.
- Account Apple gratuito: nessuna firma in CI (`CODE_SIGNING_ALLOWED=NO`).
  Il job TestFlight esiste solo come template disattivato.
- Non modificare impostazioni della repo o secrets: spiegare all'utente cosa
  configurare.

## Struttura repo

```
apps/<NomeApp>/            un'app per cartella
  project.yml              spec XcodeGen (target, bundle id, deployment target)
  Sources/                 codice SwiftUI/UIKit dell'app (solo strato UI + glue)
  Resources/               Assets.xcassets e altre risorse
  Info.plist               GENERATO da XcodeGen (git-ignored)
packages/<NomePackage>/    Swift Package con la logica NON grafica
  Package.swift            tools-version 5.9, nessuna dipendenza da UIKit/SwiftUI
  Sources/<NomePackage>/   modelli, regole, persistenza (Foundation only)
  Tests/<NomePackage>Tests/ XCTest, eseguiti anche su Linux
.github/workflows/         CI (vedi sotto)
.github/actions/setup-xcode/ composite action: seleziona Xcode, installa XcodeGen, genera il progetto
```

App presenti:

| App      | Package logica | Bundle ID                 | Deployment target | Dispositivi |
|----------|----------------|---------------------------|-------------------|-------------|
| PhotoSel | PhotoSelCore   | `com.garoth93.photosel`   | iPadOS 17.0       | solo iPad (`TARGETED_DEVICE_FAMILY: 2`) |

PhotoSel è la conversione nativa dell'app desktop Qt 6/QML
[photo-sel-qml](https://github.com/Garoth93/photo-sel-qml) (C++17). Mappa usata:

| Qt / C++ | Equivalente iPad |
|---|---|
| `scanFolder`, raggruppamento JPG+RAW+XMP, raffiche | `PhotoGrouper` (package) + `FolderAccess.listFiles` |
| `AppController` + `PhotoModel` (filtri, voti, annulla, confronto, nitidezza relativa) | `CullSession` (package, struct) + `AppStore` (@Observable) |
| `XmpSidecar` | `Xmp` (package) + `XmpWriter` (coda seriale) |
| `ImageAnalysis` (Laplaciano a tasselli, istogramma) | `ImageAnalysis` su buffer di pixel (package) + `PixelBuffers` (CGContext) |
| `ExifReader` (parser TIFF/MakerNote), `ImageLoader`, LibRaw | ImageIO: `CGImageSourceCopyPropertiesAtIndex` e `CreateThumbnailAtIndex` (anteprima RAW incorporata, poi decodifica piena allo zoom) |
| `PhotoImageProvider` thumb/screen/full + precaricamento | `ImageService`: cache su disco (miniature 480 px), NSCache, preload delle vicine |
| `Exporter` | `ExportPlanner` + `ExportRunner` (package, testati su Linux) + opzione "Aggiungi a Foto" (`PhotoLibrarySaver`) |
| `QSettings` | `AppSettings` in JSON (Application Support) tramite `JSONFileStore` |
| `FolderDialog`, drag & drop, schede SD (`QStorageInfo`) | `fileImporter` cartella + bookmark security-scoped per le recenti; le schede SD si aprono da File (iPadOS non elenca i volumi) |
| `Shortcut` QML | `.onKeyPress` (tasti singoli, serve il focus) + `Commands` per le scorciatoie con ⌘ |
| `ZoomImage` / zoom sincronizzato | `ZoomableImageView` (UIScrollView) + `ZoomSync` |
| "Mostra nella cartella" | Condividi (`ShareLink`) |

Il codice Qt originale non va modificato da questa repo.

Per aggiungere un'app: creare `apps/<Nome>/project.yml` + `Sources/` +
`Resources/`; i workflow scoprono automaticamente le cartelle in `apps/`
e i `Package.swift` in `packages/`. Il nome della cartella deve coincidere
con `name`, target e scheme nel `project.yml`.

## Convenzioni di codice

- Swift 5 language mode (`SWIFT_VERSION: 5.0` nel project.yml), tools-version
  5.9 nei package, in modo che Linux (`swift:6.0`) e Xcode 26 compilino lo
  stesso codice. Il package dichiara `.iOS(.v17)` come minimo: è solo il suo
  minimo, l'app può avere un target più alto.
- Logica, modelli e persistenza nel package: tipi `struct` value-type,
  `Codable`, `Equatable`, `Sendable`, senza `import SwiftUI`/`UIKit`.
  Tutto ciò che è testabile va lì e ha un test.
- Nell'app: `@Observable` (framework Observation) + `@MainActor`, iniettato
  con `.environment(...)` e letto con `@Environment(Tipo.self)`; viste piccole,
  stringhe UI in italiano. Target iPadOS 17.0: le API di iOS 18+ vanno
  protette con `#available`.
- Palette neutra (`Theme`): l'interfaccia non deve alterare la percezione dei
  colori delle foto; l'unico colore di carattere è l'ambra della foto corrente.
- Persistenza: JSON in Application Support tramite `JSONFileStore` (o
  SwiftData/UserDefaults quando serve, decidere caso per caso e documentarlo).
- Nessuna dipendenza esterna salvo necessità motivata; se serve, dichiararla
  nel `Package.swift` o in `project.yml > packages`, mai vendorizzare binari.
- Commit piccoli e descrittivi, in italiano o inglese ma coerenti; un commit
  per argomento. Niente identificatori di modello AI nei commit.

## Xcode e runner

- Runner: `macos-26`. Xcode fissato con `XCODE_VERSION: "26.6"` (SDK iOS 26.5) (env in ogni
  workflow) e selezionato con `xcode-select`. Se GitHub ritira la versione,
  la composite action fallisce elencando le Xcode disponibili: aggiornare il
  valore in tutti i workflow e qui.
- Toolchain Linux per i test: immagine Docker `swift:6.0-noble`.
- XcodeGen e xcbeautify installati con Homebrew a ogni run.

## CI (GitHub Actions)

| Workflow | Trigger | Cosa fa |
|----------|---------|---------|
| `build-simulator.yml` | push su ogni branch, PR, manuale | `xcodebuild build` per iOS Simulator, senza firma. Serve a vedere gli errori di compilazione. |
| `build-ipa.yml` | push su ogni branch, manuale | build Release per dispositivo con `CODE_SIGNING_ALLOWED=NO`, impacchetta `Payload/<App>.app` in `<App>-unsigned.ipa` e lo carica come artifact (30 giorni). |
| `test-linux.yml` | push su ogni branch, PR, manuale | `swift test` su ogni package in `packages/`. |
| `testflight.yml.disabled` | — | Template firmato con chiave API App Store Connect. Disattivato: GitHub ignora l'estensione `.disabled`. |

Nota: nei repo pubblici i workflow con `schedule` vengono disattivati dopo 60
giorni senza commit. Se in futuro si aggiunge un rebuild periodico (utile per
la scadenza a 7 giorni della firma gratuita), prevedere un riattivatore o usare
`workflow_dispatch`.

### Come leggere i log di CI

Con `gh` (se il token è valido):

```bash
gh run list --limit 10
gh run view <run-id> --log-failed
gh run watch <run-id>
gh run download <run-id> -n PhotoSel-unsigned-ipa
```

Con gli strumenti GitHub MCP disponibili a Claude Code (quando `gh` non è
autenticato): `actions_list` con `list_workflow_runs` per trovare il run,
`list_workflow_jobs` per i job, `get_job_logs` con `failed_only=true` e
`return_content=true` per i log dei job falliti. I log raw di `xcodebuild`
sono anche caricati come artifact `xcodebuild-*-log-<App>`.

Gli errori Swift compaiono come annotazioni `::error file=...` grazie a
`xcbeautify --renderer github-actions`.

## Regole di lavoro (per Claude)

1. Dopo **ogni push** controllare l'esito della CI e correggere da soli gli
   errori di compilazione fino a build verde. Mai dichiarare "funziona" se la
   CI non è verde: riportare l'esito reale con il link al run.
2. Non si può vedere l'interfaccia: nelle scelte grafiche ambigue usare il
   comportamento nativo iOS standard e dire all'utente cosa verificare sul
   telefono.
3. Commit piccoli e descrittivi. Mai segreti. Mai toccare impostazioni repo o
   secrets: indicare all'utente cosa configurare.
4. Se mancano informazioni (versione iOS del telefono, bundle ID, nome app),
   chiederle prima di fissarle nel codice.
5. Non si può compilare in locale su Linux: per i package si può provare
   `swift build`/`swift test` solo se un toolchain è disponibile; altrimenti
   affidarsi al job `test-linux`.

## Cartelle e permessi su iPad

- Una cartella scelta da File è leggibile solo dopo
  `startAccessingSecurityScopedResource()` e finché resta aperta
  (`AppStore.accessing`). Le XMP si scrivono nella stessa cartella: la scrittura
  va completata (`XmpWriter.flush()`) prima di chiudere l'accesso o di esportare.
- Le recenti si riaprono con un bookmark `.minimalBookmark`; per le schede SD il
  bookmark smette di valere quando la scheda viene tolta: l'app lo segnala.
- La destinazione dell'export, se diversa dalla sottocartella, ha un suo accesso
  security-scoped aperto solo durante l'export.
- La libreria Foto richiede solo il permesso "aggiungi"
  (`NSPhotoLibraryAddUsageDescription` nel `project.yml`).
