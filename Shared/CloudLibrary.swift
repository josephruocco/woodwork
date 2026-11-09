import Foundation

/// The handoff between the Mac scanner and the phone: one file in a shared
/// iCloud container. The Mac writes it after a scan, the phone picks it up on
/// launch. Replaces exporting and AirDropping `books.json` by hand.
enum CloudLibrary {
    static let container = "iCloud.com.josephruocco.bookshelf"
    static let filename = "books.json"
    static let artworkFolder = "Artwork"

    /// nil when the user isn't signed into iCloud, or the container hasn't been
    /// provisioned for this build.
    static var documentsURL: URL? {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: container) else {
            return nil
        }
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        return docs
    }

    static var fileURL: URL? { documentsURL?.appendingPathComponent(filename) }

    static var isAvailable: Bool { documentsURL != nil }

    // MARK: Writing (the Mac side)

    static func publish(_ books: [Book], artworkDirectory: URL? = nil) throws {
        guard let url = fileURL else { throw CloudError.unavailable }
        if let artworkDirectory {
            try publishArtwork(from: artworkDirectory)
        }
        let data = try JSONEncoder().encode(books)
        // Write via NSFileCoordinator so iCloud sees a clean atomic replacement
        // rather than a half-written file.
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                       error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private static func publishArtwork(from source: URL) throws {
        guard let documentsURL else { throw CloudError.unavailable }
        let destination = documentsURL.appendingPathComponent(artworkFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in (try? FileManager.default.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? [] {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing,
                                           error: &coordinationError) { coordinatedTarget in
                do {
                    try? FileManager.default.removeItem(at: coordinatedTarget)
                    try FileManager.default.copyItem(at: file, to: coordinatedTarget)
                } catch { copyError = error }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
        }
    }

    // MARK: Reading (the phone side)

    /// The file may exist in the container only as a stub until it's pulled
    /// down, so ask for it and wait briefly rather than failing on first miss.
    static func fetch(timeout: TimeInterval = 8) async -> [Book]? {
        guard let url = fileURL else { return nil }
        let fm = FileManager.default

        if !fm.fileExists(atPath: url.path) {
            try? fm.startDownloadingUbiquitousItem(at: url)
            let deadline = Date().addingTimeInterval(timeout)
            while !fm.fileExists(atPath: url.path), Date() < deadline {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        guard fm.fileExists(atPath: url.path) else { return nil }

        var result: [Book]?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            guard let data = try? Data(contentsOf: target) else { return }
            result = try? JSONDecoder().decode([Book].self, from: data)
        }
        if let books = result { await ArtworkStore.downloadCloudArtwork(for: books, timeout: timeout) }
        return (result?.isEmpty == false) ? result : nil
    }

    static var lastModified: Date? {
        guard let url = fileURL else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    enum CloudError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            "iCloud Drive isn't available. Sign in to iCloud and turn on iCloud Drive."
        }
    }
}

/// Small cover files stay outside books.json. The scanner publishes them to
/// iCloud; the phone mirrors them into the App Group so the widget can read
/// them without network access.
enum ArtworkStore {
    enum Kind: String, CaseIterable { case cover = "cover.jpg", title = "title.png" }

    static var localDirectory: URL? {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Library.appGroup
        ) {
            return group.appendingPathComponent("Artwork", isDirectory: true)
        }
        #if os(macOS)
        return URL.applicationSupportDirectory
            .appending(path: "BookshelfScanner/Artwork", directoryHint: .isDirectory)
        #else
        return nil
        #endif
    }

    static func filename(key: String, kind: Kind) -> String { "\(key)-\(kind.rawValue)" }

    static func localURL(key: String, kind: Kind) -> URL? {
        guard let directory = localDirectory else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(filename(key: key, kind: kind))
    }

    static func save(_ data: Data, key: String, kind: Kind) throws {
        guard let url = localURL(key: key, kind: kind) else { throw CocoaError(.fileNoSuchFile) }
        try data.write(to: url, options: .atomic)
    }

    static func remove(key: String) {
        for kind in Kind.allCases {
            if let url = localURL(key: key, kind: kind) { try? FileManager.default.removeItem(at: url) }
        }
    }

    static func downloadCloudArtwork(for books: [Book], timeout: TimeInterval) async {
        guard let documents = CloudLibrary.documentsURL,
              let destination = localDirectory else { return }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let cloud = documents.appendingPathComponent(CloudLibrary.artworkFolder, isDirectory: true)
        let deadline = Date().addingTimeInterval(timeout)

        for artwork in books.compactMap(\.artwork) {
            for kind in Kind.allCases {
                if kind == .cover && !artwork.hasCover { continue }
                if kind == .title && !artwork.hasTitleCrop { continue }
                let name = filename(key: artwork.key, kind: kind)
                let source = cloud.appendingPathComponent(name)
                let target = destination.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: target.path) { continue }
                if !FileManager.default.fileExists(atPath: source.path) {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: source)
                }
                while !FileManager.default.fileExists(atPath: source.path), Date() < deadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                var coordinationError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: source, options: [],
                                               error: &coordinationError) { coordinatedSource in
                    try? FileManager.default.copyItem(at: coordinatedSource, to: target)
                }
            }
        }
    }
}

/// Remembers the folder the user granted access to, so the sandbox lets us read
/// the Books database again on every later launch without re-asking.
enum LibraryBookmark {
    private static let key = "booksFolderBookmark"

    static func save(_ url: URL) {
        #if os(macOS)
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
        #endif
    }

    /// Returns the folder plus a closure to stop accessing it. Caller must call
    /// the closure, or the sandbox leaks a resource handle.
    static func resolve() -> (url: URL, release: () -> Void)? {
        #if os(macOS)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return nil }
        if stale { save(url) }
        return (url, { url.stopAccessingSecurityScopedResource() })
        #else
        return nil
        #endif
    }

    static var hasGrant: Bool {
        #if os(macOS)
        UserDefaults.standard.data(forKey: key) != nil
        #else
        false
        #endif
    }
}
