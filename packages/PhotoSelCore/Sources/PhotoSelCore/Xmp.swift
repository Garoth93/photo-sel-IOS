import Foundation

/// Rating stored in a `<name>.xmp` sidecar next to the photo.
/// Lightroom/Bridge read `xmp:Rating` (-1 = rejected) and `xmp:Label`.
/// "Kept" and the original stars of a rejected photo live in the photosel namespace.
public struct XmpRating: Equatable, Sendable {
    public var stars = 0   // 0...5
    public var flag = 0    // 1 kept, -1 rejected, 0 none
    public var label = 0   // 0 none, 1 red, 2 yellow, 3 green, 4 blue, 5 purple
    public var found = false

    public init(stars: Int = 0, flag: Int = 0, label: Int = 0, found: Bool = false) {
        self.stars = stars
        self.flag = flag
        self.label = label
        self.found = found
    }

    public var isEmpty: Bool { stars == 0 && flag == 0 && label == 0 }
}

/// Port of `XmpSidecar.cpp`: tolerant reading and in-place update that keeps
/// every other setting of an existing sidecar (e.g. Lightroom develop settings).
public enum Xmp {
    public static let labelNames = ["", "Red", "Yellow", "Green", "Blue", "Purple"]

    public static let template = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="photoSel 2">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""/>
     </rdf:RDF>
    </x:xmpmeta>

    """

    public enum WriteResult: Equatable {
        /// Nothing to save and no sidecar yet: do not create useless files.
        case skip
        /// New content of the sidecar.
        case write(String)
        /// The existing file is not an XMP packet we can update.
        case invalid
    }

    public static func parse(_ xml: String) -> XmpRating {
        var r = XmpRating(found: true)
        if let rating = Int(readValue(xml, "xmp:Rating")) {
            if rating < 0 { r.flag = -1 } else { r.stars = min(rating, 5) }
        }
        let stars = readValue(xml, "photosel:Stars")
        if !stars.isEmpty { r.stars = min(max(Int(stars) ?? 0, 0), 5) }
        if r.flag == 0 && readValue(xml, "photosel:Pick") == "1" { r.flag = 1 }
        let label = readValue(xml, "xmp:Label")
        for i in 1...5 where label.caseInsensitiveCompare(labelNames[i]) == .orderedSame {
            r.label = i
        }
        return r
    }

    public static func render(existing: String?, rating r: XmpRating) -> WriteResult {
        var xml = existing ?? ""
        if xml.isEmpty {
            if r.isEmpty { return .skip }
            xml = template
        }
        guard xml.contains("<rdf:Description") else { return .invalid }

        ensureNamespace(&xml, prefix: "xmp", uri: "http://ns.adobe.com/xap/1.0/")
        ensureNamespace(&xml, prefix: "photosel", uri: "https://photosel.app/ns/1.0/")

        let lrRating = r.flag == -1 ? -1 : r.stars
        setValue(&xml, "xmp:Rating", String(lrRating))
        if r.label > 0 || hasValue(xml, "xmp:Label") {
            setValue(&xml, "xmp:Label", labelNames[min(max(r.label, 0), 5)])
        }
        setValue(&xml, "photosel:Pick", r.flag == 1 ? "1" : "0")
        setValue(&xml, "photosel:Stars", String(r.stars))
        return .write(xml)
    }

    // MARK: - Helpers (regex based, like the Qt version)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are built from escaped constants: they always compile.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func firstCapture(_ re: NSRegularExpression, in s: String) -> String? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func readValue(_ xml: String, _ qname: String) -> String {
        let q = NSRegularExpression.escapedPattern(for: qname)
        if let v = firstCapture(regex("\\b\(q)\\s*=\\s*\"([^\"]*)\""), in: xml) {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let v = firstCapture(regex("<\(q)>([^<]*)</\(q)>"), in: xml) {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func hasValue(_ xml: String, _ qname: String) -> Bool {
        let q = NSRegularExpression.escapedPattern(for: qname)
        return matches(regex("\\b\(q)\\s*="), xml) || xml.contains("<\(qname)>")
    }

    static func ensureNamespace(_ xml: inout String, prefix: String, uri: String) {
        guard !xml.contains("xmlns:\(prefix)=") else { return }
        guard let r = xml.range(of: "<rdf:Description") else { return }
        xml.insert(contentsOf: "\n    xmlns:\(prefix)=\"\(uri)\"", at: r.upperBound)
    }

    static func setValue(_ xml: inout String, _ qname: String, _ value: String) {
        let q = NSRegularExpression.escapedPattern(for: qname)
        let v = NSRegularExpression.escapedTemplate(for: value)
        let attr = regex("\\b(\(q)\\s*=\\s*)\"[^\"]*\"")
        let full = NSRange(location: 0, length: (xml as NSString).length)
        if matches(attr, xml) {
            xml = attr.stringByReplacingMatches(in: xml, range: full, withTemplate: "$1\"\(v)\"")
            return
        }
        let elem = regex("(<\(q)>)[^<]*(</\(q)>)")
        if matches(elem, xml) {
            xml = elem.stringByReplacingMatches(in: xml, range: full, withTemplate: "$1\(v)$2")
            return
        }
        guard let r = xml.range(of: "<rdf:Description") else { return }
        xml.insert(contentsOf: "\n    \(qname)=\"\(value)\"", at: r.upperBound)
    }
}
