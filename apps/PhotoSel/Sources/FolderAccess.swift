import Foundation
import PhotoSelCore

/// Access to folders outside the app (Files, SD card readers, external drives).
/// On iPadOS a picked folder is readable only while its security scope is open;
/// recent folders are reopened through a bookmark.
enum FolderAccess {
    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

/// Writes XMP sidecars in order, off the main thread.
final class XmpWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "photosel.xmp", qos: .utility)

    /// `completion` runs on the main actor with the sidecar URL (nil if no file) or an error message.
    func write(_ rating: XmpRating, to url: URL, completion: @escaping @MainActor (URL?, String?) -> Void) {
        queue.async {
            let existing = (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
            var resultURL: URL? = existing == nil ? nil : url
            var message: String?
            switch Xmp.render(existing: existing, rating: rating) {
            case .skip:
                break
            case .invalid:
                message = "\(url.lastPathComponent) non è un file XMP valido: valutazione non salvata"
            case .write(let xml):
                do {
                    try Data(xml.utf8).write(to: url, options: .atomic)
                    resultURL = url
                } catch {
                    message = "Impossibile salvare la valutazione in \(url.lastPathComponent)"
                }
            }
            let finalURL = resultURL
            let finalMessage = message
            Task { @MainActor in completion(finalURL, finalMessage) }
        }
    }

    /// Waits until every queued write is done.
    func flush() { queue.sync {} }
}
