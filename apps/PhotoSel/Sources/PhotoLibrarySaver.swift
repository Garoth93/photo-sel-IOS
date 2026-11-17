import Foundation
import Photos
import PhotoSelCore

/// Adds exported photos to the Photos library (add-only permission).
/// JPG/HEIC + RAW of the same shot become one asset with the RAW as alternate.
enum PhotoLibrarySaver {
    static func save(_ groups: [[URL]]) async -> (saved: Int, error: String?) {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return (0, "Accesso a Foto negato: abilitalo in Impostazioni > Privacy > Foto")
        }
        var saved = 0
        var firstError: String?
        for files in groups {
            let images = files.filter { FileKinds.isSupported($0.pathExtension) }
            guard let primary = images.first(where: { !FileKinds.isRaw($0.pathExtension) }) ?? images.first else { continue }
            let raw = images.first { FileKinds.isRaw($0.pathExtension) && $0 != primary }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(with: .photo, fileURL: primary, options: options)
                    if let raw {
                        request.addResource(with: .alternatePhoto, fileURL: raw, options: options)
                    }
                }
                saved += 1
            } catch {
                if firstError == nil { firstError = "\(primary.lastPathComponent) non aggiunta a Foto (\(error.localizedDescription))" }
            }
        }
        return (saved, firstError)
    }
}
