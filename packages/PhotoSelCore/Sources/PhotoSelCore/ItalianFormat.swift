import Foundation

/// Locale-independent formatting (Italian conventions), so that tests give
/// the same result on Linux and iOS.
public enum ItalianFormat {
    /// Like Qt's `QString::number(v, 'g', n)` without exponent: 2.8 -> "2,8", 11 -> "11".
    public static func compact(_ value: Double, significant: Int, decimalSeparator: String = ",") -> String {
        guard value.isFinite, value != 0 else { return "0" }
        let magnitude = Int(floor(log10(abs(value)))) + 1
        let decimals = max(0, significant - magnitude)
        var s = String(format: "%.\(decimals)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// One decimal with comma: 2.45 -> "2,5" (rounded half away from zero).
    public static func oneDecimal(_ value: Double) -> String {
        let r = (value * 10).rounded() / 10
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }

    /// Decimal (base 1000) sizes, as shown by the Files app: "980 byte", "12,3 MB".
    public static func dataSize(_ bytes: Int64) -> String {
        if bytes < 1000 { return "\(bytes) byte" }
        let units = ["kB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = -1
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return oneDecimal(value) + " " + units[unit]
    }

    /// "6000 × 4000  (24,0 MP)"
    public static func dimensions(width: Int, height: Int) -> String {
        guard width > 0, height > 0 else { return "" }
        let mp = Double(width) * Double(height) / 1_000_000
        return "\(width) × \(height)  (\(oneDecimal(mp)) MP)"
    }

    /// "1 foto" / "3 foto"; "1 file" / "3 file" (invariable in Italian, kept for clarity).
    public static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)" }
}
