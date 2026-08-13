import WidgetKit
import SwiftUI
import AppIntents

enum WidgetShelf: Int, AppEnum {
    case one = 1
    case two
    case three
    case four
    case five
    case six

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shelf"
    static let caseDisplayRepresentations: [WidgetShelf: DisplayRepresentation] = [
        .one: "Shelf 1",
        .two: "Shelf 2",
        .three: "Shelf 3",
        .four: "Shelf 4",
        .five: "Shelf 5",
        .six: "Shelf 6"
    ]
}

struct SelectShelfIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "WoodWork Shelf"
    static let description = IntentDescription("Choose a different shelf for each widget.")

    @Parameter(title: "Books", default: .one)
    var shelf: WidgetShelf
}

struct ShelfEntry: TimelineEntry {
    let date: Date
    let books: [Book]
    let theme: ShelfTheme
}

struct Provider: AppIntentTimelineProvider {
    /// Enough to fill three shelf rows on the large widget, small enough that a
    /// day of entries stays well inside WidgetKit's archive budget.
    private let poolSize = 60

    func placeholder(in context: Context) -> ShelfEntry {
        ShelfEntry(date: .now, books: .samples, theme: ShelfSettings.loadTheme())
    }

    func snapshot(for configuration: SelectShelfIntent, in context: Context) async -> ShelfEntry {
        entry(at: .now, from: Library.load(), variation: configuration.shelf.rawValue)
    }

    func timeline(for configuration: SelectShelfIntent, in context: Context) async -> Timeline<ShelfEntry> {
        let library = Library.load()
        let hour = Calendar.current.date(bytruncating: .now)
        let entries = (0..<12).map {
            entry(
                at: hour.addingTimeInterval(Double($0) * 3600),
                from: library,
                variation: configuration.shelf.rawValue
            )
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// A fresh draw each hour, seeded by that hour so re-rendering the same entry
    /// never reshuffles the shelf under you.
    private func entry(at date: Date, from library: [Book], variation: Int) -> ShelfEntry {
        let hourSeed = UInt64(date.timeIntervalSince1970 / 3600)
        let shelfSeed = UInt64(variation) &* 0x9E37_79B9_7F4A_7C15
        var rng = SeededRNG(seed: hourSeed ^ shelfSeed ^ fnv1a("woodwork-widget"))
        return ShelfEntry(
            date: date,
            books: Array(library.shuffled(using: &rng).prefix(poolSize)),
            theme: ShelfSettings.loadTheme()
        )
    }
}

private extension Calendar {
    func date(bytruncating date: Date) -> Date {
        self.date(from: dateComponents([.year, .month, .day, .hour], from: date)) ?? date
    }
}

struct BookshelfWidgetView: View {
    var entry: ShelfEntry
    var body: some View {
        ShelfView(books: entry.books, theme: entry.theme)
            .containerBackground(for: .widget) { Color.black }
            // Tapping anywhere opens the app, which lists this hour's books.
            .widgetURL(URL(string: "bookshelf://shelf"))
    }
}

@main
struct BookshelfWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "BookshelfWidget",
            intent: SelectShelfIntent.self,
            provider: Provider()
        ) { entry in
            BookshelfWidgetView(entry: entry)
        }
        .configurationDisplayName("WoodWork")
        .description("A random handful of your library, on a shelf. Refreshes every hour.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
