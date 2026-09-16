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
    @Environment(\.openURL) private var openURL
    @StateObject private var calibreDiscovery = CalibreDiscovery()
    @State private var books = Library.load()
    @State private var theme = ShelfSettings.loadTheme()
    @State private var widgetShelves: [Int] = []
    @State private var selectedShelf = 1
    @State private var showDemo = ShelfSettings.showDemoBooks
    @State private var importing = false
    @State private var message: String?
    @State private var showingCalibre = false
    @State private var calibrePassword = ""
    @State private var calibreLibraries: [CalibreLibrary] = []
    @State private var syncingCalibre = false
    @State private var calibreServerReachable: Bool?
    @State private var shelfVariations = Dictionary(
        uniqueKeysWithValues: WidgetShelfRegistry.shelfRange.map {
            ($0, WidgetShelfRegistry.variation(for: $0))
        }
    )
    @AppStorage("calibreServerAddress") private var calibreServerAddress = ""
    @AppStorage("calibreServerUsername") private var calibreServerUsername = ""
    @AppStorage("calibreLibraryID") private var calibreLibraryID = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                widgetPager

                themeCard
                shelfNowCard
                demoCard
                calibreCard
                footerRow
                supportLinks

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Text(Library.hasOwnLibrary
                     ? libraryStatus
                     : "Showing a public domain shelf. Connect to Calibre or import a library file to see your own books.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(appBackground)
        .refreshable {
            await refreshEverything()
        }
        .onAppear {
            refreshWidgetShelves()
            Task { await syncLibrary() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshWidgetShelves()
                Task { await syncLibrary() }
            }
        }
        .onChange(of: theme) { _, newTheme in
            ShelfSettings.saveTheme(newTheme)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: showDemo) { _, on in
            ShelfSettings.showDemoBooks = on
            books = Library.load()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onOpenURL(perform: openWidgetShelf)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            handle(result)
        }
        .sheet(isPresented: $showingCalibre) {
            calibreConnectionSheet
        }
    }

    private var visibleWidgetShelves: [Int] {
        widgetShelves.isEmpty ? [1] : widgetShelves
    }

    private var selectedShelfBooks: [Book] {
        Book.onWidgetShelf(
            books,
            shelf: selectedShelf,
            count: 60,
            variation: shelfVariations[selectedShelf] ?? 0
        )
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

            HStack(spacing: 10) {
                Button {
                    reshuffleSelectedShelf()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    openRandomBook()
                } label: {
                    Label("Random", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.45, green: 0.29, blue: 0.18))
            }
        }
    }

    private func shelfPreview(_ shelf: Int) -> some View {
        ShelfView(
            books: Book.onWidgetShelf(
                books,
                shelf: shelf,
                count: 60,
                variation: shelfVariations[shelf] ?? 0
            ),
            theme: theme,
            layoutVariant: .forShelf(shelf),
            preferredRows: ShelfLayoutVariant.rowCount(forShelf: shelf)
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

    private var demoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $showDemo) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Demo books")
                        .font(.headline)
                    Text(Library.hasOwnLibrary
                         ? "Show a public domain shelf instead of your library."
                         : "A public domain shelf, until your own library syncs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color(red: 0.45, green: 0.29, blue: 0.18))
        }
        .padding(18)
        .background(panelBackground)
    }

    private var footerRow: some View {
        HStack {
            Button("Import") { importing = true }
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

    private var supportLinks: some View {
        HStack(spacing: 18) {
            Link("Support", destination: URL(string: "https://getwoodwork.app/support/")!)
            Link("Privacy", destination: URL(string: "https://getwoodwork.app/privacy/")!)
            Link(
                "Contact",
                destination: URL(string: "mailto:support@getwoodwork.app?subject=WoodWork%20Support")!
            )
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color(red: 0.45, green: 0.29, blue: 0.18))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var calibreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.title3)
                    .foregroundStyle(calibreServerReachable == false
                                     ? Color.red
                                     : Color(red: 0.45, green: 0.29, blue: 0.18))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Calibre Content Server")
                        .font(.headline)
                    Text(calibreStatusText)
                        .font(.footnote)
                        .foregroundStyle(calibreServerReachable == false ? .red : .secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(calibreServerAddress.isEmpty ? "Connect" : (calibreServerReachable == false ? "Retry" : "Sync")) {
                    showingCalibre = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(panelBackground)
    }

    private var calibreConnectionSheet: some View {
        NavigationStack {
            Form {
                if calibreDiscovery.isSearching || !calibreDiscovery.servers.isEmpty {
                    Section("Nearby Calibre Servers") {
                        if calibreDiscovery.servers.isEmpty {
                            HStack {
                                ProgressView().padding(.trailing, 6)
                                Text("Looking on your Wi-Fi network…")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(calibreDiscovery.servers) { server in
                                Button {
                                    calibreServerAddress = server.address
                                    Task { await testCalibreConnection() }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(server.name).foregroundStyle(.primary)
                                        Text(server.address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Content Server") {
                    TextField("http://192.168.1.2:8080", text: $calibreServerAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Username (optional)", text: $calibreServerUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password (optional)", text: $calibrePassword)
                }

                if !calibreLibraries.isEmpty {
                    Section("Library") {
                        Picker("Library", selection: $calibreLibraryID) {
                            ForEach(calibreLibraries) { library in
                                Text(library.name).tag(library.id)
                            }
                        }
                    }
                }

                Section {
                    Button("Test Connection") {
                        Task { await testCalibreConnection() }
                    }
                    .disabled(syncingCalibre || calibreServerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task { await syncFromCalibre(password: calibrePassword) }
                    } label: {
                        HStack {
                            if syncingCalibre { ProgressView().padding(.trailing, 4) }
                            Text(syncingCalibre ? "Syncing…" : "Connect and Sync")
                        }
                    }
                    .disabled(syncingCalibre || calibreServerAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("In Calibre, choose Connect/share → Start Content Server. Your iPhone and computer must be on the same network unless you securely expose the server remotely.")
                }

                if !calibreServerAddress.isEmpty {
                    Section {
                        Button("Stop Calibre Refresh") {
                            calibreServerAddress = ""
                            calibreServerUsername = ""
                            calibreLibraryID = ""
                            calibrePassword = ""
                            CalibreCredentials.savePassword("")
                            calibreServerReachable = nil
                            showingCalibre = false
                        }
                    } footer: {
                        Text("Books already imported from Calibre stay on your shelf.")
                    }
                }

                if let message {
                    Section("Status") { Text(message) }
                }
            }
            .navigationTitle("Connect to Calibre")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                calibrePassword = CalibreCredentials.loadPassword()
                calibreDiscovery.start()
            }
            .onDisappear { calibreDiscovery.stop() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingCalibre = false }
                }
            }
        }
    }

    private var libraryStatus: String {
        "Your combined library is stored on this device and shared with the widget."
    }

    private func syncLibrary() async {
        await syncFromCloud(quietly: true)
        if !calibreServerAddress.isEmpty {
            await syncFromCalibre(password: CalibreCredentials.loadPassword(), quietly: true)
        }
    }

    private func refreshEverything() async {
        await syncLibrary()
        refreshWidgetShelves()
        // Keep the refresh indicator visible until WidgetKit's asynchronous
        // configuration query has completed its reconciliation pass.
        try? await Task.sleep(for: .seconds(1))
        message = calibreServerReachable == false
            ? "Library refreshed. Calibre server not found."
            : "Library and widget refreshed."
    }

    private func syncFromCalibre(password: String, quietly: Bool = false) async {
        guard !syncingCalibre else { return }
        syncingCalibre = true
        defer { syncingCalibre = false }

        do {
            let client = try CalibreServerClient(
                address: calibreServerAddress,
                username: calibreServerUsername,
                password: password
            )
            let incoming = try await client.fetchBooks(libraryID: calibreLibraryID)
            let combined = Library.merged(
                Library.storedBooks(),
                with: incoming,
                replacingSources: ["calibre"]
            )
            try Library.save(combined)
            CalibreCredentials.savePassword(password)
            ShelfSettings.showDemoBooks = false
            showDemo = false
            books = combined
            WidgetCenter.shared.reloadAllTimelines()
            calibreServerReachable = true
            if !quietly {
                message = "Synced \(incoming.count) books from Calibre. \(combined.count) books total."
            }
        } catch {
            calibreServerReachable = false
            if !quietly { message = "Calibre sync failed: \(error.localizedDescription)" }
        }
    }

    private func testCalibreConnection() async {
        guard !syncingCalibre else { return }
        syncingCalibre = true
        defer { syncingCalibre = false }

        do {
            let client = try CalibreServerClient(
                address: calibreServerAddress,
                username: calibreServerUsername,
                password: calibrePassword
            )
            let libraries = try await client.fetchLibraries()
            calibreLibraries = libraries
            if !libraries.contains(where: { $0.id == calibreLibraryID }) {
                calibreLibraryID = libraries[0].id
            }
            message = libraries.count == 1
                ? "Connected to Calibre."
                : "Connected. Choose one of \(libraries.count) libraries."
            calibreServerReachable = true
        } catch {
            calibreServerReachable = false
            message = "Connection failed: \(error.localizedDescription)"
        }
    }

    private var calibreStatusText: String {
        guard !calibreServerAddress.isEmpty else {
            return "Sync your Calibre library over Wi-Fi."
        }
        if syncingCalibre { return "Checking \(calibreServerAddress)…" }
        switch calibreServerReachable {
        case true:
            return "Connected to \(calibreServerAddress)"
        case false:
            return "Server not found. Start the Calibre Content Server, then retry."
        case nil:
            return "Saved server: \(calibreServerAddress)"
        }
    }

    private func reshuffleSelectedShelf() {
        shelfVariations[selectedShelf] = WidgetShelfRegistry.reshuffle(shelf: selectedShelf)
        WidgetCenter.shared.reloadTimelines(ofKind: "BookshelfWidget")
    }

    private func openRandomBook() {
        let openable = Library.storedBooks().filter { $0.readerURL != nil }
        guard let book = openable.randomElement(), let url = book.readerURL else {
            message = "No imported books have a link that WoodWork can open yet."
            return
        }
        openURL(url)
    }

    /// Pick up whatever the Mac scanner last published. Quiet on failure —
    /// there's usually just nothing there yet, and the bundled library still
    /// shows a shelf.
    private func syncFromCloud(quietly: Bool = false) async {
        guard let incoming = await CloudLibrary.fetch() else { return }
        let combined = Library.merged(
            Library.storedBooks(),
            with: incoming,
            replacingSources: ["books", "kindle"]
        )
        guard combined != Library.storedBooks() else { return }
        do {
            try Library.save(combined)
            ShelfSettings.showDemoBooks = false
            showDemo = false
            books = combined
            WidgetCenter.shared.reloadAllTimelines()
            if !quietly {
                message = "Synced \(incoming.count) books from your Mac. \(combined.count) books total."
            }
        } catch {
            if !quietly { message = "Couldn't save the synced library: \(error.localizedDescription)" }
        }
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

            let combined = Library.merged(
                Library.storedBooks(),
                with: imported,
                replacingSources: Set(imported.map(\.source))
            )
            try Library.save(combined)
            ShelfSettings.showDemoBooks = false
            showDemo = false
            books = combined
            WidgetCenter.shared.reloadAllTimelines()
            message = "Imported \(imported.count) books. \(combined.count) books total."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    private func refreshWidgetShelves() {
        // Do not reload here: WidgetKit can retain a deleted configuration in
        // its cache, and reloading causes that ghost to render again. Query
        // after Home Screen changes have had time to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            queryCurrentWidgetShelves()
        }
    }

    private func queryCurrentWidgetShelves() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case .success(let configurations) = result else {
                Task { @MainActor in
                    widgetShelves = []
                    selectedShelf = 1
                }
                return
            }
            let configured = Array(Set(configurations.compactMap { info -> Int? in
                guard info.kind == "BookshelfWidget" else { return nil }
                return info.widgetConfigurationIntent(of: SelectShelfIntent.self)?.shelf.rawValue
            })).sorted()
            let suppressed = WidgetShelfRegistry.suppressedShelves
            let active = configured.filter { !suppressed.contains($0) }

            Task { @MainActor in
                widgetShelves = active
                let visible = active.isEmpty ? [1] : active
                if !visible.contains(selectedShelf), let first = visible.first {
                    selectedShelf = first
                }
            }
        }
    }

    private func openWidgetShelf(_ url: URL) {
        guard url.scheme == "bookshelf", url.host == "shelf",
              let component = url.pathComponents.last,
              let shelf = Int(component),
              WidgetShelfRegistry.shelfRange.contains(shelf) else { return }
        WidgetShelfRegistry.register(shelf: shelf)
        WidgetShelfRegistry.restore(shelf: shelf)
        widgetShelves = [shelf]
        selectedShelf = shelf
        message = "Synced to Home Screen Widget Shelf \(shelf)."
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
