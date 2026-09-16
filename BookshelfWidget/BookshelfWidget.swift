import WidgetKit
import SwiftUI
import AppIntents

struct ShelfEntry: TimelineEntry {
    let date: Date
    let books: [Book]
    let theme: ShelfTheme
    let shelf: Int
    let layoutVariant: ShelfLayoutVariant
}

struct Provider: AppIntentTimelineProvider {
    /// Enough to fill three shelf rows on the large widget, small enough that a
    /// day of entries stays well inside WidgetKit's archive budget.
    private let poolSize = 60

    func placeholder(in context: Context) -> ShelfEntry {
        ShelfEntry(
            date: .now,
            books: .samples,
            theme: ShelfSettings.loadTheme(),
            shelf: 1,
            layoutVariant: .balanced
        )
    }

    func snapshot(for configuration: SelectShelfIntent, in context: Context) async -> ShelfEntry {
        let shelf = configuration.shelf.rawValue
        if !context.isPreview { WidgetShelfRegistry.register(shelf: shelf) }
        let library = context.isPreview ? Library.load() : await refreshedLibrary()
        return entry(at: .now, from: library, shelf: shelf)
    }

    func timeline(for configuration: SelectShelfIntent, in context: Context) async -> Timeline<ShelfEntry> {
        let shelf = configuration.shelf.rawValue
        WidgetShelfRegistry.register(shelf: shelf)
        let library = await refreshedLibrary()
        let now = Date.now

        // Do not precompute hours of entries from one library snapshot. If the
        // Mac publishes a new scan, a short timeline lets the widget see it
        // without requiring the iPhone app to be opened first.
        return Timeline(
            entries: [entry(at: now, from: library, shelf: shelf)],
            policy: .after(now.addingTimeInterval(30 * 60))
        )
    }

    private func refreshedLibrary() async -> [Book] {
        guard let incoming = await CloudLibrary.fetch(timeout: 3) else {
            return Library.load()
        }

        let stored = Library.storedBooks()
        let combined = Library.merged(
            stored,
            with: incoming,
            replacingSources: ["books", "kindle"]
        )
        if combined != stored { try? Library.save(combined) }
        return Library.load()
    }

    /// A fresh draw each hour, seeded by that hour so re-rendering the same entry
    /// never reshuffles the shelf under you.
    private func entry(at date: Date, from library: [Book], shelf: Int) -> ShelfEntry {
        return ShelfEntry(
            date: date,
            books: Book.onWidgetShelf(
                library,
                shelf: shelf,
                at: date,
                count: poolSize,
                variation: WidgetShelfRegistry.variation(for: shelf)
            ),
            theme: ShelfSettings.loadTheme(),
            shelf: shelf,
            layoutVariant: .forShelf(shelf)
        )
    }
}

struct BookshelfWidgetView: View {
    var entry: ShelfEntry
    var body: some View {
        ShelfView(
            books: entry.books,
            theme: entry.theme,
            layoutVariant: entry.layoutVariant,
            preferredRows: ShelfLayoutVariant.rowCount(forShelf: entry.shelf)
        )
            .containerBackground(for: .widget) { Color.black }
            // Tapping anywhere opens the app, which lists this hour's books.
            .widgetURL(URL(string: "bookshelf://shelf/\(entry.shelf)"))
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
