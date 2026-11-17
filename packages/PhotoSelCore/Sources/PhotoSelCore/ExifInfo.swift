import Foundation

/// Shooting data. On iPad it is filled from ImageIO properties;
/// the formatting is ported from `ExifInfo` of the Qt app.
public struct ExifInfo: Equatable, Sendable, Codable {
    public var make = ""
    public var model = ""
    public var lens = ""
    public var captured: Date?
    public var exposure: Double = 0   // seconds
    public var fnumber: Double = 0
    public var focal: Double = 0      // mm
    public var iso = 0
    public var width = 0
    public var height = 0

    public init() {}

    public var isEmpty: Bool {
        make.isEmpty && model.isEmpty && captured == nil && exposure == 0 && fnumber == 0 && iso == 0
    }

    public var exposureText: String {
        guard exposure > 0 else { return "" }
        if exposure >= 1 {
            let r = (exposure * 10).rounded() / 10
            return ItalianFormat.compact(r, significant: 3) + "″"
        }
        return "1/\(Int((1 / exposure).rounded()))"
    }

    public var apertureText: String {
        fnumber > 0 ? "f/" + ItalianFormat.compact(fnumber, significant: 2, decimalSeparator: ".") : ""
    }

    public var focalText: String { focal > 0 ? "\(Int(focal.rounded())) mm" : "" }

    public var isoText: String { iso > 0 ? "ISO \(iso)" : "" }

    /// "SONY" + "ILCE-6700" -> "Sony ILCE-6700"; "Canon" + "Canon EOS R6" -> "Canon EOS R6".
    public var cameraText: String {
        let make = self.make.trimmingCharacters(in: .whitespaces)
        let model = self.model.trimmingCharacters(in: .whitespaces)
        if model.isEmpty { return make }
        if make.isEmpty || model.lowercased().hasPrefix(make.lowercased()) { return model }
        let m = make.lowercased()
        return m.prefix(1).uppercased() + m.dropFirst() + " " + model
    }

    /// "1/500   f/2.8   ISO 400   35 mm" (the line under the thumbnails).
    public var summaryLine: String {
        [exposureText, apertureText, isoText, focalText].filter { !$0.isEmpty }.joined(separator: "   ")
    }
}
