import Foundation

/// The handoff between the Mac scanner and the phone: one file in a shared
/// iCloud container. The Mac writes it after a scan, the phone picks it up on
/// launch. Replaces exporting and AirDropping `books.json` by hand.
enum CloudLibrary {
    static let container = "iCloud.com.josephruocco.bookshelf"
    static let filename = "books.json"

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

    static func publish(_ books: [Book]) throws {
        guard let url = fileURL else { throw CloudError.unavailable }
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
