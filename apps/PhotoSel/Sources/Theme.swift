import SwiftUI

/// Neutral palette: the interface must not alter the perception of the photos'
/// colours. The only "character" colour is the amber of the selected frame.
enum Theme {
    static let chrome = Color(hex: 0x1d1d1f)    // bars and panels
    static let panel = Color(hex: 0x242426)
    static let raised = Color(hex: 0x2e2e31)    // hover, fields
    static let line = Color(hex: 0x38383b)
    static let text = Color(hex: 0xe7e5e0)
    static let muted = Color(hex: 0x9a968f)
    static let faint = Color(hex: 0x626059)
    static let accent = Color(hex: 0xe3b341)    // current frame
    static let accentInk = Color(hex: 0x1d1d1f)
    static let keep = Color(hex: 0x5fbf87)
    static let reject = Color(hex: 0xe2625a)

    /// Colour labels (same as Lightroom). Index 0 = none.
    static let labelColors: [Color] = [.clear, Color(hex: 0xe2625a), Color(hex: 0xe3c341),
                                       Color(hex: 0x5fbf87), Color(hex: 0x4f93e0), Color(hex: 0xa57ee0)]
    static let labelNames = ["Nessuna", "Rosso", "Giallo", "Verde", "Blu", "Viola"]

    /// Viewer background: dark neutral grey, black, mid grey.
    static let loupeBackgrounds: [Color] = [Color(hex: 0x2b2b2b), .black, Color(hex: 0x6b6b6b)]

    static func loupeBackground(_ i: Int) -> Color { loupeBackgrounds[((i % 3) + 3) % 3] }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

enum ViewMode: String, CaseIterable {
    case loupe, grid, compare

    var title: String {
        switch self {
        case .loupe: return "Singola"
        case .grid: return "Griglia"
        case .compare: return "Confronto"
        }
    }

    var systemImage: String {
        switch self {
        case .loupe: return "photo"
        case .grid: return "square.grid.2x2"
        case .compare: return "rectangle.split.2x1"
        }
    }

    var key: String {
        switch self {
        case .loupe: return "E"
        case .grid: return "G"
        case .compare: return "C"
        }
    }
}
