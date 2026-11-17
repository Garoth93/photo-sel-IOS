import Foundation

/// User settings (Qt's QSettings), saved as JSON by the app.
/// Decoding is lenient: missing or invalid keys take the default.
public struct AppSettings: Codable, Equatable, Sendable {
    public var autoAdvance = true
    public var writeXmp = true
    public var preferRaw = false
    public var burstGapMs = 1000
    public var loupeBackground = 0
    public var infoPanelVisible = true
    public var compareSize = 3
    public var filmstripVisible = true
    public var export = ExportOptions()
    public var recents: [RecentFolder] = []

    public static let burstGapRange = 200...5000
    public static let loupeBackgroundNames = ["Grigio scuro", "Nero", "Grigio medio"]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        autoAdvance = (try? c.decodeIfPresent(Bool.self, forKey: .autoAdvance)) ?? d.autoAdvance
        writeXmp = (try? c.decodeIfPresent(Bool.self, forKey: .writeXmp)) ?? d.writeXmp
        preferRaw = (try? c.decodeIfPresent(Bool.self, forKey: .preferRaw)) ?? d.preferRaw
        burstGapMs = Self.clampGap((try? c.decodeIfPresent(Int.self, forKey: .burstGapMs)) ?? d.burstGapMs)
        loupeBackground = Self.wrapBackground((try? c.decodeIfPresent(Int.self, forKey: .loupeBackground)) ?? d.loupeBackground)
        infoPanelVisible = (try? c.decodeIfPresent(Bool.self, forKey: .infoPanelVisible)) ?? d.infoPanelVisible
        compareSize = min(max((try? c.decodeIfPresent(Int.self, forKey: .compareSize)) ?? d.compareSize, 2), 4)
        filmstripVisible = (try? c.decodeIfPresent(Bool.self, forKey: .filmstripVisible)) ?? d.filmstripVisible
        export = (try? c.decodeIfPresent(ExportOptions.self, forKey: .export)) ?? d.export
        recents = (try? c.decodeIfPresent([RecentFolder].self, forKey: .recents)) ?? d.recents
    }

    public static func clampGap(_ ms: Int) -> Int { min(max(ms, burstGapRange.lowerBound), burstGapRange.upperBound) }
    public static func wrapBackground(_ i: Int) -> Int { ((i % 3) + 3) % 3 }

    /// "Scatti a meno di 1,0 secondi l'uno dall'altro formano una raffica."
    public var burstGapText: String {
        "Scatti a meno di \(ItalianFormat.oneDecimal(Double(burstGapMs) / 1000)) secondi l'uno dall'altro formano una raffica."
    }
}

/// A folder opened recently. On iPad a folder outside the app can be reopened
/// only through its security-scoped bookmark.
public struct RecentFolder: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    /// Path at the time it was opened (identity and subtitle only).
    public var path: String
    public var bookmark: Data
    public var opened: Date

    public var id: String { path }

    public init(name: String, path: String, bookmark: Data, opened: Date) {
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.opened = opened
    }

    /// Parent folder for the subtitle: ".../DCIM/100MSDCF" -> "DCIM".
    public var parentName: String {
        URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }

    public static let limit = 8

    /// Most recent first, no duplicates, at most `limit`.
    public static func adding(_ folder: RecentFolder, to list: [RecentFolder]) -> [RecentFolder] {
        Array(([folder] + list.filter { $0.path != folder.path }).prefix(limit))
    }
}
