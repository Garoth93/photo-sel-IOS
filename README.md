# photoSel per iPad

App nativa iPad (Swift + SwiftUI) per scegliere le foto della fotocamera: scorri gli
scatti, tieni i migliori ed esporta solo quelli. È la conversione dell'app desktop
Qt/QML [photo-sel-qml](https://github.com/Garoth93/photo-sel-qml), con le stesse
regole: raffiche, nitidezza relativa, valutazioni in sidecar XMP compatibili con
Lightroom, export in un solo passaggio.

Il codice si scrive senza Mac: GitHub Actions compila su runner macOS e produce un
`.ipa` **non firmato**, da firmare e installare con Sideloadly o SideStore.

## Scaricare e installare l'app

1. Apri **Actions** → **build-ipa** → il run più recente con la spunta verde.
   Serve essere loggati su GitHub, anche se la repo è pubblica.
2. In fondo alla pagina, sezione **Artifacts**, scarica **PhotoSel-unsigned-ipa**
   e estrai lo zip: dentro c'è `PhotoSel-unsigned.ipa`.
3. Firmalo e installalo sull'iPad con Sideloadly (account Apple gratuito) come
   per le altre app. Bundle ID: `com.garoth93.photosel`.
4. Con l'account gratuito la firma dura 7 giorni: poi va ripetuta.

Ogni push su qualunque branch genera un nuovo `.ipa`; si può anche avviare a mano
con **Run workflow**. Gli artifact restano scaricabili 30 giorni.

## Flusso di lavoro su iPad

1. **Apri** una cartella da File: memoria dell'iPad, iCloud Drive, scheda SD
   (lettore USB-C o fotocamera collegata), disco esterno. Le cartelle aperte
   restano tra le recenti.
   - Le foto vengono cercate anche nelle sottocartelle (fino a 6 livelli): puoi
     aprire la scheda intera o la cartella `DCIM`.
   - JPG, RAW e XMP con lo stesso nome sono una foto sola anche se stanno in
     cartelle diverse (per esempio `DCIM/100MSDCF/DSC0001.JPG` e `RAW/DSC0001.ARW`).
   - Se la numerazione della fotocamera è ripartita e lo stesso nome compare in
     cartelle diverse per scatti diversi, decide l'ora di scatto: i file vengono
     abbinati solo se sono stati scattati a meno di 2 minuti l'uno dall'altro.
   - Le cartelle create dall'export (`selezionate`, `da_eliminare` o quella scelta)
     non vengono lette come foto da valutare.
2. **Valuta** con i pulsanti della barra in basso o con la tastiera.
   - P tieni, X scarta, U togli. Da 1 a 5 le stelle, da 6 a 9 le etichette colore.
   - Con "Avanza dopo il voto" attivo passa da sola alla foto successiva.
   - Scorri a destra e sinistra per cambiare foto, doppio tocco per il 100%.
3. **Controlla le raffiche** col confronto (C): ◆ indica la più nitida, lo zoom è
   sincronizzato tra i riquadri.
4. **Esporta** una sola volta: tenute, con almeno N stelle oppure tutte tranne le
   scartate; scegli formati, destinazione, copia o sposta, una sottocartella per
   formato, spostamento delle scartate in `da_eliminare`, e se aggiungerle anche
   alla libreria Foto.

**Aprire in Lightroom.** Dal pannello informazioni ("Apri in Lightroom…", tasto L)
per la foto corrente, oppure dalla griglia con **Seleziona** per più foto insieme
(Tutte, Tenute o a tocchi). Si apre il foglio di condivisione di iPadOS: scegli
Lightroom e le foto vengono importate. Il menu accanto sceglie cosa inviare di ogni
foto: il RAW se c'è (predefinito), il JPG se c'è, o tutti i file.

Le valutazioni sono salvate in un file `.xmp` accanto a ogni foto, nello stesso
formato della versione desktop: le valutazioni fatte sull'iPad si ritrovano sul PC
e viceversa, e Lightroom/Bridge leggono stelle, scartate (rating −1) ed etichette.

## Differenze rispetto alla versione desktop

| Desktop (Qt) | iPad |
|---|---|
| Rilevamento automatico delle schede SD | iPadOS non elenca i volumi: la scheda si apre da File |
| Solo la cartella aperta, JPG e RAW nella stessa cartella | Anche le sottocartelle, JPG e RAW abbinati anche in cartelle diverse |
| Trascina una cartella nella finestra | Apri cartella da File; le recenti si riaprono con un tocco |
| Parser EXIF interno + LibRaw | ImageIO di sistema: legge i RAW supportati da iPadOS (ARW, CR2/CR3, NEF, RAF, DNG, ORF, RW2…) |
| Anteprima RAW sempre dall'JPEG incorporato | Anteprima incorporata per scorrere, decodifica RAW piena quando zoomi al 100% |
| "Mostra in Esplora file" | Condividi / apri in Lightroom, anche più foto insieme |
| Solo copia/spostamento su disco | In più: aggiungi alla libreria Foto (JPG + RAW come unica foto) |
| Solo tastiera e mouse | Gesti touch + tutte le scorciatoie con tastiera esterna |

## Struttura

```
apps/PhotoSel/              app SwiftUI (viste, ImageIO, accesso alle cartelle)
  project.yml               spec XcodeGen (il .xcodeproj si genera in CI)
packages/PhotoSelCore/      logica senza UI, testata anche su Linux
  PhotoGrouper              abbinamento JPG+RAW+XMP anche tra cartelle, ordine cronologico, raffiche
  FolderScanner             lettura ricorsiva della cartella aperta
  CullSession               filtri, voti, annulla, finestra del confronto, nitidezza
  Xmp                       lettura/scrittura sidecar compatibili Lightroom
  ImageAnalysis             nitidezza (Laplaciano a tasselli) e istogramma
  Export                    piano di esportazione e copia/spostamento
  AppSettings               impostazioni e cartelle recenti
.github/workflows/          test-linux, build-simulator, build-ipa
```

Regole di lavoro e dettagli della CI: [CLAUDE.md](CLAUDE.md).
