import Foundation
import SQLite3
import Vision
import ImageIO
import UniformTypeIdentifiers

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

        // Sandboxed, so the library folder is whatever the user granted us —
        // remembered from last time unless they're pointing us somewhere new.
        let grant = booksDBOverride == nil ? LibraryBookmark.resolve() : nil
        defer { grant?.release() }

        let selectedRoot = booksDBOverride ?? grant?.url
        var found: [Book] = []
        do {
            if let selectedRoot, let db = Self.sqliteFile(in: selectedRoot) {
                status = "Reading Apple Books…"
                var appleBooks = try read(db, query: Self.appleBooksQuery, source: "books")
                if let covers = Self.coverDataStore(in: selectedRoot) {
                    appleBooks = extractArtwork(from: appleBooks, coverDataStore: covers)
                } else {
                    needsFolderPick = true
                    status = "Books found. Choose the Apple Books Data folder to include real covers."
                }
                found += appleBooks
            } else {
                status = "Choose your Apple Books folder to get started."
                needsFolderPick = true
                return
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
        publishToCloud()
    }

    /// Hand the result to the phone. This is the whole point of the Mac app —
    /// exporting a file by hand is the fallback, not the flow.
    func publishToCloud() {
        guard !books.isEmpty else { return }
        guard CloudLibrary.isAvailable else {
            status += " iCloud Drive is off, so use Save books.json… instead."
            return
        }
        do {
            try CloudLibrary.publish(books, artworkDirectory: CoverExtractor.outputDirectory)
            status += " Synced to your iPhone via iCloud."
        } catch {
            status += " iCloud sync failed: \(error.localizedDescription)"
        }
    }

    /// Accept the Apple Books Data folder, the legacy BKLibrary folder, or the
    /// sqlite file itself. Data is preferred because it also grants cover-cache
    /// access.
    static func sqliteFile(in url: URL) -> URL? {
        if url.pathExtension == "sqlite" { return url }
        let candidates = [
            url,
            url.appending(path: "Documents/BKLibrary"),
            url.appending(path: "Data/Documents/BKLibrary")
        ]
        for directory in candidates {
            if let match = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ))?.first(where: { $0.pathExtension == "sqlite" }) { return match }
        }
        return nil
    }

    static func coverDataStore(in url: URL) -> URL? {
        let candidates = [
            url.appending(path: "Library/Caches/BCCoverCache-1/BICDiskDataStore"),
            url.appending(path: "Data/Library/Caches/BCCoverCache-1/BICDiskDataStore")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
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

    /// ZBOOKID is the ASIN, which is what
    /// `kindle://book/?action=open&asin=…` wants.
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

    private func extractArtwork(from input: [Book], coverDataStore: URL) -> [Book] {
        var output = input
        var matched = 0
        for index in output.indices {
            guard let assetID = output[index].assetID,
                  let artwork = CoverExtractor.extract(
                    book: output[index], assetID: assetID, dataStore: coverDataStore
                  ) else { continue }
            output[index].artwork = artwork
            matched += 1
            if matched.isMultiple(of: 10) {
                status = "Reading cover art… \(matched)/\(input.count)"
            }
        }
        if matched > 0 { status = "Matched cover art for \(matched) Apple Books titles."
        }
        return output
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
                // Only remember hits. A zero here usually means a timeout or a
                // rate-limit, and caching that would make a transient failure
                // permanent — which is how a 549-hit library became 140.
                if pages > 0 {
                    cache[books[index].id] = pages
                    books[index].pages = pages
                    books[index].pagesEstimated = false
                }
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

private enum CoverExtractor {
    static var outputDirectory: URL {
        let url = URL.applicationSupportDirectory
            .appending(path: "BookshelfScanner/Artwork", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func extract(book: Book, assetID: String, dataStore: URL) -> BookArtwork? {
        let directory = dataStore.appending(path: assetID, directoryHint: .isDirectory)
        guard let coverURL = bestCover(in: directory),
              let source = CGImageSourceCreateWithURL(coverURL as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

        let key = String(fnv1a("\(book.source ?? "book")|\(assetID)"), radix: 16)
        let cover = resized(original, maxWidth: 240) ?? original
        guard write(cover, to: outputDirectory.appendingPathComponent(
            ArtworkStore.filename(key: key, kind: .cover)
        ), type: UTType.jpeg.identifier as CFString, quality: 0.76) else { return nil }

        let primary = averageRGB(original, rect: CGRect(
            x: 0, y: 0, width: original.width, height: original.height
        ))
        let accent = averageRGB(original, rect: CGRect(
            x: 0, y: 0, width: original.width,
            height: max(1, Int(Double(original.height) * 0.32))
        ))
        let ink: UInt32 = luminance(primary) > 0.56 ? 0x201A16 : 0xFFF8E8

        var hasTitle = false
        if let crop = titleCrop(in: original, title: book.title) {
            let title = resized(crop, maxWidth: 360) ?? crop
            hasTitle = write(title, to: outputDirectory.appendingPathComponent(
                ArtworkStore.filename(key: key, kind: .title)
            ), type: UTType.png.identifier as CFString, quality: 1)
        }

        return BookArtwork(key: key, primaryRGB: primary, accentRGB: accent,
                           inkRGB: ink, hasCover: true, hasTitleCrop: hasTitle)
    }

    private static func bestCover(in directory: URL) -> URL? {
        let supported = Set(["jpg", "jpeg", "heic", "png"])
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .max { pixelArea($0) < pixelArea($1) }
    }

    private static func pixelArea(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return 0 }
        return width * height
    }

    private static func resized(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let width = maxWidth
        let height = max(1, Int((Double(image.height) / Double(image.width)) * Double(width)))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL, type: CFString,
                              quality: Double) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    private static func averageRGB(_ image: CGImage, rect: CGRect) -> UInt32 {
        guard let crop = image.cropping(to: rect),
              let context = CGContext(data: nil, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0x655044 }
        context.interpolationQuality = .medium
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0x655044 }
        return UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
    }

    private static func luminance(_ rgb: UInt32) -> Double {
        let r = Double((rgb >> 16) & 0xff) / 255
        let g = Double((rgb >> 8) & 0xff) / 255
        let b = Double(rgb & 0xff) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func titleCrop(in image: CGImage, title: String) -> CGImage? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.025
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }

        let wanted = tokenSet(title)
        let matches = (request.results ?? []).filter { observation in
            guard let candidate = observation.topCandidates(1).first else { return false }
            return !wanted.isDisjoint(with: tokenSet(candidate.string))
        }
        guard !matches.isEmpty else { return nil }
        let normalized = matches.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        let padding: CGFloat = 0.025
        let padded = normalized.insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixels = CGRect(
            x: padded.minX * CGFloat(image.width),
            y: (1 - padded.maxY) * CGFloat(image.height),
            width: padded.width * CGFloat(image.width),
            height: padded.height * CGFloat(image.height)
        ).integral
        return image.cropping(to: pixels)
    }

    private static func tokenSet(_ value: String) -> Set<String> {
        Set(value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 })
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
