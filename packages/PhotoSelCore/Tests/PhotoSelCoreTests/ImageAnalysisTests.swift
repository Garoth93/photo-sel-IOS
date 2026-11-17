import XCTest
@testable import PhotoSelCore

final class ImageAnalysisTests: XCTestCase {
    func testFlatImageHasZeroSharpness() {
        let gray = [UInt8](repeating: 128, count: 64 * 64)
        XCTAssertEqual(ImageAnalysis.sharpness(gray: gray, width: 64, height: 64), 0)
        XCTAssertEqual(ImageAnalysis.sharpness(gray: [], width: 8, height: 8), 0)
    }

    func testDetailIsSharperThanBlur() {
        let w = 96, h = 96
        var sharp = [UInt8](repeating: 0, count: w * h)
        var soft = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                sharp[y * w + x] = ((x / 2 + y / 2) % 2 == 0) ? 230 : 20                     // fine checkerboard
                soft[y * w + x] = UInt8(125 + Int(100 * sin(Double(x) / 12) * cos(Double(y) / 12)))  // smooth
            }
        }
        let a = ImageAnalysis.sharpness(gray: sharp, width: w, height: h)
        let b = ImageAnalysis.sharpness(gray: soft, width: w, height: h)
        XCTAssertGreaterThan(a, b * 10)
    }

    func testSharpnessRespectsStride() {
        let w = 40, h = 40, stride = 48
        var padded = [UInt8](repeating: 255, count: stride * h)   // padding is noise-free white
        var tight = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let v: UInt8 = (x + y) % 3 == 0 ? 200 : 40
                padded[y * stride + x] = v
                tight[y * w + x] = v
            }
        }
        XCTAssertEqual(ImageAnalysis.sharpness(gray: padded, width: w, height: h, bytesPerRow: stride),
                       ImageAnalysis.sharpness(gray: tight, width: w, height: h), accuracy: 1e-9)
    }

    func testHistogram() {
        // 3 pixels: pure red, pure green, mid gray; plus a black pixel (extreme bin)
        let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 128, 128, 128, 255, 0, 0, 0, 255]
        let h = ImageAnalysis.histogram(rgba: rgba, width: 4, height: 1)
        let bins = ImageAnalysis.histogramBins
        XCTAssertEqual(h.count, 4 * bins)
        XCTAssertEqual(h[bins + 32], 1)        // red channel, gray pixel (128 >> 2 = 32)
        XCTAssertEqual(h[bins + 63], 1)        // red 255: extreme bin, clamped to 1
        XCTAssertEqual(h[0], 1)                // luminance of the black pixel
        XCTAssertTrue(h.allSatisfy { $0 >= 0 && $0 <= 1 })
        XCTAssertEqual(ImageAnalysis.histogram(rgba: [], width: 0, height: 0).count, 4 * bins)
    }
}
