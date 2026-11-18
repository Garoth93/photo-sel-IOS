import XCTest
@testable import PhotoSelCore

final class FolderScannerTests: XCTestCase {
    func testRecursiveListingSkipsHiddenExcludedAndDeepFolders() throws {
        let fm = FileManager.default
        let root = tempDir()
        defer { try? fm.removeItem(at: root) }
        let files = [
            "DCIM/100MSDCF/DSC0001.JPG",
            "DCIM/100MSDCF/DSC0001.xmp",
            "DCIM/100MSDCF/clip.MP4",          // not a photo
            "RAW/DSC0001.ARW",
            "top.jpg",
            ".hidden/x.jpg",
            "DCIM/.Trashes/y.jpg",
            "selezionate/jpg/DSC0001.JPG",      // export destination: excluded
            "a/b/c/d/e/f/g/deep.jpg",           // depth 7: beyond the limit
            "a/b/c/d/e/f/ok.jpg",               // depth 6: listed
        ]
        for f in files {
            let url = root.appendingPathComponent(f)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: url)
        }
        let entries = try FolderScanner.listFiles(in: root, excluding: [root.appendingPathComponent("selezionate")])
        let names = Set(entries.map { PhotoGrouper.relativePath(of: $0.url.deletingLastPathComponent(), to: root) + "/" + $0.url.lastPathComponent })
        XCTAssertEqual(names, [
            "DCIM/100MSDCF/DSC0001.JPG", "DCIM/100MSDCF/DSC0001.xmp", "RAW/DSC0001.ARW",
            "/top.jpg", "a/b/c/d/e/f/ok.jpg",
        ])
        XCTAssertEqual(entries.first { $0.ext == "arw" }?.size, 3)

        let photos = PhotoGrouper.group(entries, preferRaw: false)
        XCTAssertEqual(photos.count, 3)
        XCTAssertEqual(photos.first { $0.baseName == "DSC0001" }?.files.count, 3)
    }

    func testUnreadableRootThrows() {
        XCTAssertThrowsError(try FolderScanner.listFiles(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
    }
}
