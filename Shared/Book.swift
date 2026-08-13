import Foundation
import CoreGraphics
import SwiftUI

struct Book: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let author: String
    var pages: Int
    /// True when `pages` is a fallback guess rather than a real count.
    var pagesEstimated: Bool
    /// Apple Books asset id or Kindle ASIN. Optional so libraries exported
    /// before deep links existed still decode.
    var assetID: String? = nil
    /// "books" or "kindle" — decides which app a tap opens.
    var source: String? = nil

    var shortTitle: String {
        // Subtitles after a colon are noise on a 20pt-wide spine.
        title.split(separator: ":", maxSplits: 1).first.map(String.init) ?? title
    }

    var spineTitle: String {
        shortTitle
            .replacingOccurrences(of: " and ", with: " & ")
            .replacingOccurrences(of: " the ", with: " ")
            .replacingOccurrences(of: " The ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SpineTypographyStyle {
    case classic
    case modern
    case literary
    case scholarly
}

// MARK: - Pulling a book off the shelf

extension Book {
    /// Where this book actually lives. A widget can't launch another app
    /// directly — WidgetKit hands a `Link` URL to the containing app — so this
    /// is what the app forwards to once it receives the tap.
    var readerURL: URL? {
        guard let assetID, !assetID.isEmpty else { return nil }
        switch source {
        case "kindle": return URL(string: "kindle://book?action=open&asin=\(assetID)")
        default: return URL(string: "ibooks://assetid/\(assetID)")
        }
    }

    /// The books the widget is showing right now. Seeded by the clock hour, so
    /// the app's list matches the shelf on the home screen.
    static func onShelfNow(_ library: [Book], at date: Date = .now,
                           count: Int = 24, variation: Int = 0) -> [Book] {
        guard !library.isEmpty else { return [] }
        let hourSeed = UInt64(date.timeIntervalSince1970 / 3600)
        let variationSeed = UInt64(bitPattern: Int64(variation)) &* 0x9E37_79B9_7F4A_7C15
        var rng = SeededRNG(seed: hourSeed ^ variationSeed ^ fnv1a("woodwork"))
        return Array(library.shuffled(using: &rng).prefix(max(1, count)))
    }
}

// MARK: - Physical dimensions

extension Book {
    /// ~0.075pt per page puts a 300-page paperback at 22pt and keeps a 1500-page
    /// manual from eating the whole shelf.
    var spineWidth: CGFloat { min(44, max(9, CGFloat(pages) * 0.075)) }

    /// Books aren't all the same height. Deterministic per title so a book always
    /// looks like itself.
    var heightFactor: CGFloat { 0.84 + 0.16 * CGFloat(hashUnit(1)) }

    var cloth: Cloth { Cloth.palette[Int(stableHash(2) % UInt64(Cloth.palette.count))] }
    var textureIndex: Int { Int(stableHash(3) % 12) + 1 }
    var typographyStyle: SpineTypographyStyle {
        let haystack = "\(title) \(author)".lowercased()

        if haystack.contains(anyOf: [
            "meditations", "plato", "aristotle", "virgil", "homer", "aurelius",
            "dickens", "tolstoy", "woolf", "eliot", "odyssey", "middlemarch"
        ]) {
            return .classic
        }

        if haystack.contains(anyOf: [
            "habit", "mindset", "success", "self", "productivity", "guide",
            "how to", "startup", "improve", "leadership", "daily", "work"
        ]) {
            return .modern
        }

        if haystack.contains(anyOf: [
            "analysis", "statistics", "calculus", "mathematics", "probability",
            "physics", "econometrics", "journal", "science", "theory", "models"
        ]) {
            return .scholarly
        }

        return .literary
    }

    private func hashUnit(_ salt: UInt64) -> Double {
        Double(stableHash(salt) % 10_000) / 10_000
    }

    private func stableHash(_ salt: UInt64) -> UInt64 { fnv1a(id + "#\(salt)") }
}

private extension String {
    func contains(anyOf needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}

/// Swift's `Hasher` is seeded per process, which would reshuffle every spine
/// colour on each widget launch. FNV-1a is stable across runs.
func fnv1a(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in s.utf8 { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
    return h
}

// MARK: - Cloth colours

struct Cloth {
    let r, g, b: Double

    static let palette: [Cloth] = [
        Cloth(r: 0.43, g: 0.17, b: 0.17), Cloth(r: 0.18, g: 0.28, b: 0.22),
        Cloth(r: 0.15, g: 0.22, b: 0.31), Cloth(r: 0.65, g: 0.46, b: 0.23),
        Cloth(r: 0.85, g: 0.81, b: 0.71), Cloth(r: 0.35, g: 0.19, b: 0.29),
        Cloth(r: 0.17, g: 0.35, b: 0.35), Cloth(r: 0.55, g: 0.29, b: 0.18),
        Cloth(r: 0.29, g: 0.31, b: 0.35), Cloth(r: 0.37, g: 0.42, b: 0.22),
        Cloth(r: 0.49, g: 0.25, b: 0.18), Cloth(r: 0.22, g: 0.22, b: 0.23),
        Cloth(r: 0.69, g: 0.54, b: 0.24), Cloth(r: 0.56, g: 0.23, b: 0.23),
    ]

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    var isLight: Bool { luminance > 0.5 }
}

// MARK: - Seeded shuffle

/// SplitMix64 — so a given hour always draws the same shelf, and WidgetKit
/// re-rendering an entry doesn't reshuffle the books under you.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Library storage

enum Library {
    /// Must match the App Group on both the app and the widget target.
    static let appGroup = "group.com.josephruocco.bookshelf"

    static var sharedFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("books.json")
    }

    /// App Group first (imported at runtime), then a copy bundled at build time,
    /// then samples. The bundled fallback is what makes this work without a paid
    /// developer account, where App Groups aren't available.
    static func load() -> [Book] {
        if let url = sharedFile, let books = decode(url), !books.isEmpty { return books }
        if let url = Bundle.main.url(forResource: "books", withExtension: "json"),
           let books = decode(url), !books.isEmpty { return books }
        return .samples
    }

    static func save(_ books: [Book]) throws {
        guard let url = sharedFile else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(books).write(to: url, options: .atomic)
    }

    private static func decode(_ url: URL) -> [Book]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Book].self, from: data)
    }
}

// MARK: - Theme settings

enum ShelfTheme: String, CaseIterable, Codable, Identifiable {
    case classic
    case walnut
    case realistic
    case artsy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: "Classic"
        case .walnut: "Dark Oak"
        case .realistic: "White Built-In"
        case .artsy: "Artsy"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: "Clean shelf, balanced contrast"
        case .walnut: "Thick oak frame, deep warm cubbies"
        case .realistic: "Cream molding, softly recessed shelves"
        case .artsy: "Paper backdrop, illustrated finish"
        }
    }
}

enum ShelfSettings {
    private static let themeKey = "shelfTheme"
    private static let layoutKey = "shelfLayoutOptions"

    static func loadTheme() -> ShelfTheme {
        guard let defaults = UserDefaults(suiteName: Library.appGroup),
              let raw = defaults.string(forKey: themeKey),
              let theme = ShelfTheme(rawValue: raw) else {
            return .classic
        }
        return theme
    }

    static func saveTheme(_ theme: ShelfTheme) {
        UserDefaults(suiteName: Library.appGroup)?.set(theme.rawValue, forKey: themeKey)
    }

    static func loadLayoutOptions() -> ShelfLayoutOptions {
        guard let defaults = UserDefaults(suiteName: Library.appGroup),
              let data = defaults.data(forKey: layoutKey),
              let decoded = try? JSONDecoder().decode(ShelfLayoutOptions.self, from: data) else {
            return .default
        }
        return decoded.clamped
    }

    static func saveLayoutOptions(_ options: ShelfLayoutOptions) {
        guard let data = try? JSONEncoder().encode(options.clamped) else { return }
        UserDefaults(suiteName: Library.appGroup)?.set(data, forKey: layoutKey)
    }
}

struct ShelfLayoutOptions: Codable, Hashable {
    var totalBooks: Int
    var allowsStacks: Bool
    var outwardFacingBooks: Int
    var variation: Int

    static let `default` = ShelfLayoutOptions(
        totalBooks: 24,
        allowsStacks: true,
        outwardFacingBooks: 1,
        variation: 0
    )

    var clamped: ShelfLayoutOptions {
        ShelfLayoutOptions(
            totalBooks: min(72, max(6, totalBooks)),
            allowsStacks: allowsStacks,
            outwardFacingBooks: min(6, max(0, outwardFacingBooks)),
            variation: min(12, max(0, variation))
        )
    }
}

extension Array where Element == Book {
    static var samples: [Book] {
        [("Moby-Dick", "Herman Melville", 720), ("The Left Hand of Darkness", "Ursula K. Le Guin", 304),
         ("Meditations", "Marcus Aurelius", 254), ("Middlemarch", "George Eliot", 904),
         ("Dune", "Frank Herbert", 688), ("The Odyssey", "Homer", 560),
         ("Beloved", "Toni Morrison", 324), ("Infinite Jest", "David Foster Wallace", 1079),
         ("The Sea, The Sea", "Iris Murdoch", 528), ("Piranesi", "Susanna Clarke", 245),
         ("Gödel, Escher, Bach", "Douglas Hofstadter", 777), ("Pale Fire", "Vladimir Nabokov", 246),
         ("The Waves", "Virginia Woolf", 297), ("Blood Meridian", "Cormac McCarthy", 351),
         ("A Wizard of Earthsea", "Ursula K. Le Guin", 183), ("Wolf Hall", "Hilary Mantel", 653)]
            .map { Book(id: $0.0, title: $0.0, author: $0.1, pages: $0.2, pagesEstimated: false) }
    }
}
