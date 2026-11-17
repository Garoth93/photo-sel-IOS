import Foundation

/// Port of `ImageAnalysis.cpp`, working on plain pixel buffers so it runs
/// (and is tested) without any image framework.
public enum ImageAnalysis {
    public static let histogramBins = 64

    /// Sharpness index: variance of the Laplacian computed per 32 px tile,
    /// mean of the sharpest 10% of the tiles. Rewards the subject in focus
    /// even when the background is blurred (typical of wildlife with a tele lens).
    /// `gray` holds `height` rows of `bytesPerRow` bytes (one byte per pixel).
    public static func sharpness(gray: [UInt8], width w: Int, height h: Int, bytesPerRow: Int? = nil) -> Double {
        let stride = bytesPerRow ?? w
        guard w >= 16, h >= 16, gray.count >= stride * h else { return 0 }
        let tile = 32
        let tx = max(1, (w - 2) / tile)
        let ty = max(1, (h - 2) / tile)
        var scores: [Double] = []
        scores.reserveCapacity(tx * ty)

        gray.withUnsafeBufferPointer { px in
            for by in 0..<ty {
                for bx in 0..<tx {
                    var sum = 0.0, sum2 = 0.0
                    var n = 0
                    let y0 = 1 + by * tile, y1 = min(h - 1, y0 + tile)
                    let x0 = 1 + bx * tile, x1 = min(w - 1, x0 + tile)
                    guard y0 < y1, x0 < x1 else { continue }
                    for y in y0..<y1 {
                        let up = (y - 1) * stride, row = y * stride, dn = (y + 1) * stride
                        for x in x0..<x1 {
                            let c = Int(px[row + x])
                            let lap = Int(px[up + x]) + Int(px[dn + x]) + Int(px[row + x - 1]) + Int(px[row + x + 1]) - 4 * c
                            let d = Double(lap)
                            sum += d
                            sum2 += d * d
                            n += 1
                        }
                    }
                    if n > 0 {
                        let mean = sum / Double(n)
                        scores.append(sum2 / Double(n) - mean * mean)
                    }
                }
            }
        }
        guard !scores.isEmpty else { return 0 }
        scores.sort(by: >)
        let k = max(1, scores.count / 10)
        return scores.prefix(k).reduce(0, +) / Double(k)
    }

    /// Histogram: 4 consecutive channels (luminance, R, G, B) of `histogramBins`
    /// values each, normalised 0...1 to the peak. The peak ignores the extreme
    /// bins, so clipped highlights/shadows do not flatten the rest.
    /// `rgba` holds 4 bytes per pixel in R, G, B, x order.
    public static func histogram(rgba: [UInt8], width w: Int, height h: Int, bytesPerRow: Int? = nil) -> [Float] {
        let bins = histogramBins
        guard w > 0, h > 0 else { return [Float](repeating: 0, count: 4 * bins) }
        let stride = bytesPerRow ?? w * 4
        guard rgba.count >= stride * (h - 1) + w * 4 else { return [Float](repeating: 0, count: 4 * bins) }
        var c = [UInt32](repeating: 0, count: 4 * bins)
        rgba.withUnsafeBufferPointer { px in
            for y in 0..<h {
                var i = y * stride
                for _ in 0..<w {
                    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                    let l = (r * 54 + g * 183 + b * 19) >> 8
                    c[l >> 2] += 1
                    c[bins + (r >> 2)] += 1
                    c[2 * bins + (g >> 2)] += 1
                    c[3 * bins + (b >> 2)] += 1
                    i += 4
                }
            }
        }
        var peak: UInt32 = 1
        for ch in 0..<4 {
            for i in 1..<(bins - 1) { peak = max(peak, c[ch * bins + i]) }
        }
        return c.map { min(1, Float($0) / Float(peak)) }
    }
}
