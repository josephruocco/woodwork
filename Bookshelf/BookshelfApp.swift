import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

@main
struct BookshelfApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var books = Library.load()
    @State private var theme = ShelfSettings.loadTheme()
    @State private var widgetShelves = WidgetShelfRegistry.activeShelves()
    @State private var selectedShelf = 1
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                widgetPager

                themeCard
                shelfNowCard
                footerRow

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Text("Run WoodWork Scanner on your Mac, then AirDrop `books.json` here.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(appBackground)
        .onAppear(perform: refreshWidgetShelves)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshWidgetShelves() }
        }
        .onChange(of: theme) { _, newTheme in
            ShelfSettings.saveTheme(newTheme)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onOpenURL(perform: openWidgetShelf)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            handle(result)
        }
    }

    private var visibleWidgetShelves: [Int] {
        widgetShelves.isEmpty ? [1] : widgetShelves
    }

    private var selectedShelfBooks: [Book] {
        Book.onWidgetShelf(books, shelf: selectedShelf, count: 60)
    }

    private var featured: [Book] {
        Array(selectedShelfBooks.prefix(24))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("WoodWork")
                .font(.system(size: 36, weight: .light, design: .serif))
                .foregroundStyle(Color(red: 0.20, green: 0.16, blue: 0.13))
            Spacer()
            Text("\(books.count) books")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mood")
                .font(.headline)

            Menu {
                Picker("Theme", selection: $theme) {
                    ForEach(ShelfTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(theme.label)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(theme.subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
            }
        }
        .padding(18)
        .background(panelBackground)
    }

    private var widgetPager: some View {
        VStack(spacing: 11) {
            TabView(selection: $selectedShelf) {
                ForEach(visibleWidgetShelves, id: \.self) { shelf in
                    shelfPreview(shelf)
                        .tag(shelf)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 350)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Widget Shelf \(selectedShelf)")
                        .font(.subheadline.weight(.semibold))
                    Text(ShelfLayoutVariant.forShelf(selectedShelf).label + " layout")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 7) {
                    ForEach(visibleWidgetShelves, id: \.self) { shelf in
                        Button {
                            withAnimation(.snappy) { selectedShelf = shelf }
                        } label: {
                            Circle()
                                .fill(shelf == selectedShelf ? Color.primary : Color.secondary.opacity(0.25))
                                .frame(width: 7, height: 7)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show Widget Shelf \(shelf)")
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func shelfPreview(_ shelf: Int) -> some View {
        ShelfView(
            books: Book.onWidgetShelf(books, shelf: shelf, count: 60),
            theme: theme,
            layoutVariant: .forShelf(shelf)
        )
        .frame(height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(theme == .artsy ? 0.18 : 0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme == .artsy ? 0.10 : 0.14), radius: 18, y: 10)
    }

    private var shelfNowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("On Your Shelf")
                        .font(.headline)
                    Text("Books displayed by Widget Shelf \(selectedShelf).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Shelf \(selectedShelf)", systemImage: "books.vertical")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(featured) { book in
                    BookRow(book: book)
                    if book.id != featured.last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.90))
            )
        }
        .padding(18)
        .background(panelBackground)
    }

    private var footerRow: some View {
        HStack {
            Button("Import books.json…") { importing = true }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.45, green: 0.29, blue: 0.18))

            Spacer()

            Text("\(books.count) books indexed")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(panelBackground)
    }

    private func handle(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            let imported = try JSONDecoder().decode([Book].self, from: Data(contentsOf: url))
            guard !imported.isEmpty else {
                message = "That file has no books in it."
                return
            }

            try Library.save(imported)
            books = imported
            WidgetCenter.shared.reloadAllTimelines()
            message = "Imported \(imported.count) books. The widget will refresh shortly."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    private func refreshWidgetShelves() {
        let active = WidgetShelfRegistry.activeShelves()
        widgetShelves = active
        let visible = active.isEmpty ? [1] : active
        if !visible.contains(selectedShelf), let first = visible.first {
            selectedShelf = first
        }
    }

    private func openWidgetShelf(_ url: URL) {
        guard url.scheme == "bookshelf", url.host == "shelf",
              let component = url.pathComponents.last,
              let shelf = Int(component),
              WidgetShelfRegistry.shelfRange.contains(shelf) else { return }
        WidgetShelfRegistry.register(shelf: shelf)
        refreshWidgetShelves()
        selectedShelf = shelf
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.95, blue: 0.92),
                Color(red: 0.92, green: 0.89, blue: 0.84)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.42), lineWidth: 1)
            )
    }
}

private struct BookRow: View {
    let book: Book
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = book.readerURL { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(red: book.cloth.r, green: book.cloth.g, blue: book.cloth.b))
                    .frame(width: max(4, book.spineWidth * 0.3), height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(book.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(book.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text("\(book.pages)p")
                    .font(.caption2)
                    .foregroundStyle(book.pagesEstimated ? .tertiary : .secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(book.readerURL == nil)
    }
}
