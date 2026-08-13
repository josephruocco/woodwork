import Foundation
import SQLite3

/// Reads the local Apple Books and Kindle libraries, then fills in page counts
/// from Open Library. Page count is the whole point: it's what sets spine
/// thickness on the shelf.
@MainActor
final class LibraryScanner: ObservableObject {
    @Published var status = "Ready."
    @Published var books: [Book] = []
    @Published var busy = false
    @Published var needsFolderPick = false

    private let session = URLSession(configuration: .ephemeral)

    // MARK: Local library databases

    private static var booksDB: URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary")
        return (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "sqlite" }
    }

    private static var kindleDB: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.amazon.Lassen/Data/Library/Protected/BookData.sqlite")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Scan

    func scan(booksDBOverride: URL? = nil) async {
        busy = true
        needsFolderPick = false
        defer { busy = false }

        var found: [Book] = []
        do {
            if let db = booksDBOverride ?? Self.booksDB {
                status = "Reading Apple Books…"
                found += try read(db, query: Self.appleBooksQuery, source: "books")
            }
            if let db = Self.kindleDB {
                status = "Reading Kindle…"
                found += (try? read(db, query: Self.kindleQuery, source: "kindle")) ?? []
            }
        } catch {
            status = "Couldn't read the library: \(error.localizedDescription)"
            needsFolderPick = true
            return
        }

        guard !found.isEmpty else {
            status = "No books found. Point me at the BKLibrary folder instead."
            needsFolderPick = true
            return
        }

        // Same book can appear once per device it was downloaded to.
        var seen = Set<String>()
        found = found.filter { seen.insert($0.id).inserted }

        books = found
        await fillPageCounts()
    }

    /// Everything the shelf needs. Type 1 is an ebook; type 5 rows are series
    /// containers ("Incerto"), not books.
    /// ZASSETID is what `ibooks://assetid/…` wants, so tapping a spine can open
    /// the actual book.
    private static let appleBooksQuery = """
        SELECT ZTITLE, ZAUTHOR, ZPAGECOUNT, ZASSETID FROM ZBKLIBRARYASSET
        WHERE ZTITLE IS NOT NULL AND ZCONTENTTYPE = 1
          AND (ZISHIDDEN IS NULL OR ZISHIDDEN = 0)
        """

    /// ZBOOKID is the ASIN, which is what `kindle://book?asin=…` wants.
    private static let kindleQuery = """
        SELECT ZDISPLAYTITLE, ZDISPLAYAUTHOR, 0, ZBOOKID FROM ZBOOK
        WHERE ZDISPLAYTITLE IS NOT NULL AND (ZRAWISDICTIONARY IS NULL OR ZRAWISDICTIONARY = 0)
        """

    private func read(_ url: URL, query: String, source: String) throws -> [Book] {
        // Copy first: both apps keep a hot WAL, and opening in place risks a
        // partial read (or an -shm the sandbox won't hand us).
        let tmp = URL.temporaryDirectory.appending(path: "scan-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: url, to: tmp)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.copyItem(
                at: URL(filePath: url.path + suffix),
                to: URL(filePath: tmp.path + suffix))
        }
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tmp.path + s) } }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var out: [Book] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let title = column(stmt, 0), author = column(stmt, 1) ?? "Unknown"
            guard let title, !title.isEmpty else { continue }
            let pages = Int(sqlite3_column_int(stmt, 2))
            out.append(Book(id: "\(title)|\(author)", title: title, author: author,
                            pages: pages, pagesEstimated: pages <= 0,
                            assetID: column(stmt, 3), source: source))
        }
        return out
    }

    private func column(_ stmt: OpaquePointer?, _ i: Int32) -> String? {
        sqlite3_column_text(stmt, i).map { String(cString: $0) }
    }

    // MARK: Page counts

    private func fillPageCounts() async {
        var cache = PageCache.load()
        let missing = books.enumerated().filter { $0.element.pages <= 0 }

        var done = 0
        // Four at a time — Open Library is free and asks callers to be polite.
        for chunk in stride(from: 0, to: missing.count, by: 4).map({
            Array(missing[$0..<min($0 + 4, missing.count)])
        }) {
            let results = await withTaskGroup(of: (Int, Int).self) { group in
                for (index, book) in chunk {
                    let cached = cache[book.id]
                    group.addTask { [weak self] in
                        if let cached { return (index, cached) }
                        return (index, await self?.lookup(book) ?? 0)
                    }
                }
                return await group.reduce(into: [(Int, Int)]()) { $0.append($1) }
            }
            for (index, pages) in results {
                cache[books[index].id] = pages
                if pages > 0 { books[index].pages = pages; books[index].pagesEstimated = false }
            }
            done += chunk.count
            status = "Looking up page counts… \(done)/\(missing.count)"
        }

        PageCache.save(cache)

        // Anything still unknown gets the library's own median, so it sits on the
        // shelf at a believable thickness instead of vanishing.
        let known = books.filter { !$0.pagesEstimated }.map(\.pages).sorted()
        let median = known.isEmpty ? 300 : known[known.count / 2]
        for i in books.indices where books[i].pages <= 0 {
            books[i].pages = median
            books[i].pagesEstimated = true
        }

        let real = books.count { !$0.pagesEstimated }
        status = "\(books.count) books — \(real) with real page counts, \(books.count - real) estimated."
    }

    private func lookup(_ book: Book) async -> Int {
        var c = URLComponents(string: "https://openlibrary.org/search.json")!
        c.queryItems = [
            .init(name: "title", value: book.title),
            .init(name: "author", value: book.author),
            .init(name: "fields", value: "number_of_pages_median"),
            .init(name: "limit", value: "1"),
        ]
        guard let url = c.url else { return 0 }
        var request = URLRequest(url: url)
        request.setValue("bookshelf-widget/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]],
              let pages = docs.first?["number_of_pages_median"] as? Int
        else { return 0 }
        return (50...4000).contains(pages) ? pages : 0
    }

    // MARK: Export

    func export(to url: URL) throws {
        try JSONEncoder().encode(books).write(to: url, options: .atomic)
    }
}

/// Lookups are the slow part; remember them so a rescan is instant.
private enum PageCache {
    static var url: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "BookshelfScanner")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "pagecache.json")
    }

    static func load() -> [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: url))) ?? [:]
    }

    static func save(_ cache: [String: Int]) {
        try? JSONEncoder().encode(cache).write(to: url, options: .atomic)
    }
}
