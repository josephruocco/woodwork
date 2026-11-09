import Foundation
import Combine
import Security
import Vision
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum CalibreServerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(Int)
    case emptyLibrary

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter the full Content Server address, such as http://192.168.1.2:8080."
        case .invalidResponse:
            "That address did not return a Calibre Content Server response."
        case .server(let status):
            status == 401 ? "Calibre rejected that username or password." : "Calibre returned HTTP \(status)."
        case .emptyLibrary:
            "Calibre connected, but that library contains no books."
        }
    }
}

struct CalibreServerClient {
    let baseURL: URL
    let username: String
    let password: String

    init(address: String, username: String = "", password: String = "") throws {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw CalibreServerError.invalidURL
        }
        baseURL = url
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    func fetchLibraries() async throws -> [CalibreLibrary] {
        let raw = try await json(path: "/ajax/library-info")
        guard let info = raw as? [String: Any] else {
            throw CalibreServerError.invalidResponse
        }

        let defaultID = (info["default_library"] as? String)
            ?? (info["default_library_id"] as? String)
        let map = info["library_map"] as? [String: Any] ?? [:]
        var libraries = map.map { id, rawName in
            CalibreLibrary(id: id, name: (rawName as? String) ?? id)
        }
        if libraries.isEmpty, let defaultID, !defaultID.isEmpty {
            libraries = [CalibreLibrary(id: defaultID, name: defaultID)]
        }
        guard !libraries.isEmpty else { throw CalibreServerError.invalidResponse }
        return libraries.sorted {
            if $0.id == defaultID { return true }
            if $1.id == defaultID { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func fetchBooks(libraryID requestedLibraryID: String? = nil) async throws -> [Book] {
        let libraries = try await fetchLibraries()
        let libraryID = libraries.first(where: { $0.id == requestedLibraryID })?.id
            ?? libraries[0].id

        let encodedLibrary = libraryID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? libraryID
        let searchJSON = try await json(path: "/ajax/search/\(encodedLibrary)")
        guard let search = searchJSON as? [String: Any],
              let rawIDs = search["book_ids"] as? [Any] else {
            throw CalibreServerError.invalidResponse
        }

        let ids = rawIDs.compactMap { value -> Int? in
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String { return Int(string) }
            return nil
        }
        guard !ids.isEmpty else { throw CalibreServerError.emptyLibrary }

        var books: [Book] = []
        for batch in ids.chunked(into: 100) {
            let list = batch.map(String.init).joined(separator: ",")
            var components = URLComponents(url: baseURL.appending(path: "/ajax/books"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "ids", value: list),
                URLQueryItem(name: "library_id", value: libraryID)
            ]
            guard let url = components?.url else { throw CalibreServerError.invalidURL }
            let payload = try await json(url: url)
            guard let records = payload as? [String: Any] else {
                throw CalibreServerError.invalidResponse
            }
            books.append(contentsOf: batch.compactMap { id in
                guard let metadata = records[String(id)] as? [String: Any] else { return nil }
                return makeBook(id: id, libraryID: libraryID, metadata: metadata)
            })
        }

        guard !books.isEmpty else { throw CalibreServerError.emptyLibrary }
        for chunk in stride(from: 0, to: books.count, by: 6).map({
            Array($0..<min($0 + 6, books.count))
        }) {
            let artwork = await withTaskGroup(of: (Int, BookArtwork?).self) { group in
                for index in chunk {
                    let book = books[index]
                    group.addTask {
                        (index, await coverArtwork(for: book, libraryID: libraryID))
                    }
                }
                return await group.reduce(into: [(Int, BookArtwork?)]()) { $0.append($1) }
            }
            for (index, result) in artwork where result != nil { books[index].artwork = result }
        }
        return books
    }

    private func coverArtwork(for book: Book, libraryID: String) async -> BookArtwork? {
        guard let fragment = URLComponents(string: book.assetID ?? "")?.fragment,
              let idPart = fragment.split(separator: "&").first(where: { $0.hasPrefix("book_id=") }),
              let id = Int(idPart.dropFirst("book_id=".count)) else { return nil }
        let encodedLibrary = libraryID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? libraryID
        let url = baseURL
            .appending(path: "get/cover/\(id)/\(encodedLibrary)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        if !username.isEmpty {
            let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return nil }
        return CoverArtworkProcessor.process(data: data, book: book, identifier: "\(libraryID)|\(id)")
    }

    private func makeBook(id: Int, libraryID: String, metadata: [String: Any]) -> Book? {
        guard let title = metadata["title"] as? String, !title.isEmpty else { return nil }
        let authors = (metadata["authors"] as? [String]) ?? []
        let author = authors.isEmpty ? "Unknown author" : authors.joined(separator: " & ")
        let uuid = (metadata["uuid"] as? String) ?? String(id)
        let reportedPages = (metadata["pages"] as? NSNumber)?.intValue ?? 0
        let estimatedPages = estimatePages(from: metadata["format_metadata"])
        let pages = reportedPages > 0 ? reportedPages : estimatedPages

        var details = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        details?.fragment = "book_id=\(id)&library_id=\(libraryID)&panel=book_details"

        return Book(
            id: "calibre:\(uuid)",
            title: title,
            author: author,
            pages: pages,
            pagesEstimated: reportedPages <= 0,
            assetID: details?.url?.absoluteString,
            source: "calibre"
        )
    }

    private func estimatePages(from raw: Any?) -> Int {
        guard let formats = raw as? [String: Any] else { return 240 }
        let sizes = formats.values.compactMap { value -> Int? in
            guard let metadata = value as? [String: Any],
                  let size = metadata["size"] as? NSNumber else { return nil }
            return size.intValue
        }
        guard let largest = sizes.max(), largest > 0 else { return 240 }
        return min(2000, max(40, Int((Double(largest) / 1500.0).rounded())))
    }

    private func json(path: String) async throws -> Any {
        let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return try await json(url: baseURL.appending(path: relativePath))
    }

    private func json(url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !username.isEmpty {
            let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CalibreServerError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CalibreServerError.server(http.statusCode)
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CalibreServerError.invalidResponse
        }
    }
}

enum CoverArtworkProcessor {
    static func process(data: Data, book: Book, identifier: String) -> BookArtwork? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let key = String(fnv1a("calibre|\(identifier)"), radix: 16)
        let cover = resized(original, maxWidth: 240) ?? original
        guard let coverData = encoded(cover, type: UTType.jpeg.identifier as CFString, quality: 0.76),
              (try? ArtworkStore.save(coverData, key: key, kind: .cover)) != nil else { return nil }

        let primary = averageRGB(original, heightFraction: 1)
        let accent = averageRGB(original, heightFraction: 0.32)
        let ink: UInt32 = luminance(primary) > 0.56 ? 0x201A16 : 0xFFF8E8
        var hasTitle = false
        if let crop = titleCrop(in: original, title: book.title),
           let titleData = encoded(resized(crop, maxWidth: 360) ?? crop,
                                   type: UTType.png.identifier as CFString, quality: 1) {
            hasTitle = (try? ArtworkStore.save(titleData, key: key, kind: .title)) != nil
        }
        return BookArtwork(key: key, primaryRGB: primary, accentRGB: accent,
                           inkRGB: ink, hasCover: true, hasTitleCrop: hasTitle)
    }

    private static func resized(_ image: CGImage, maxWidth: Int) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let height = max(1, Int(Double(image.height) / Double(image.width) * Double(maxWidth)))
        guard let context = CGContext(data: nil, width: maxWidth, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }

    private static func encoded(_ image: CGImage, type: CFString, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func averageRGB(_ image: CGImage, heightFraction: Double) -> UInt32 {
        let height = max(1, Int(Double(image.height) * heightFraction))
        guard let crop = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: height)),
              let context = CGContext(data: nil, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 0x655044 }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return 0x655044 }
        return UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2])
    }

    private static func luminance(_ rgb: UInt32) -> Double {
        0.2126 * Double((rgb >> 16) & 0xff) / 255
            + 0.7152 * Double((rgb >> 8) & 0xff) / 255
            + 0.0722 * Double(rgb & 0xff) / 255
    }

    private static func titleCrop(in image: CGImage, title: String) -> CGImage? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.025
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return nil }
        let wanted = tokens(title)
        let matches = (request.results ?? []).filter {
            guard let text = $0.topCandidates(1).first?.string else { return false }
            return !wanted.isDisjoint(with: tokens(text))
        }
        guard !matches.isEmpty else { return nil }
        let normalized = matches.map(\.boundingBox).reduce(CGRect.null) { $0.union($1) }
        let padded = normalized.insetBy(dx: -0.025, dy: -0.025)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return image.cropping(to: CGRect(
            x: padded.minX * CGFloat(image.width),
            y: (1 - padded.maxY) * CGFloat(image.height),
            width: padded.width * CGFloat(image.width),
            height: padded.height * CGFloat(image.height)
        ).integral)
    }

    private static func tokens(_ value: String) -> Set<String> {
        Set(value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 })
    }
}

struct CalibreLibrary: Identifiable, Hashable {
    let id: String
    let name: String
}

struct CalibreDiscoveredServer: Identifiable, Hashable {
    let name: String
    let address: String

    var id: String { address }
}

@MainActor
final class CalibreDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published private(set) var servers: [CalibreDiscoveredServer] = []
    @Published private(set) var isSearching = false

    private let browser = NetServiceBrowser()
    private var resolving: [NetService] = []

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard !isSearching else { return }
        servers = []
        resolving = []
        isSearching = true
        browser.searchForServices(ofType: "_calibre._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        resolving.forEach { $0.stop() }
        resolving = []
        isSearching = false
    }

    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        Task { @MainActor in
            service.delegate = self
            resolving.append(service)
            service.resolve(withTimeout: 8)
        }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in
            guard let rawHost = sender.hostName, sender.port > 0 else { return }
            let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
            var serverPath = ""
            if let record = sender.txtRecordData(),
               let pathData = NetService.dictionary(fromTXTRecord: record)["path"],
               var path = String(data: pathData, encoding: .utf8) {
                if path.hasSuffix("/opds") { path.removeLast(5) }
                if path != "/" { serverPath = path }
            }
            let address = "http://\(host):\(sender.port)\(serverPath)"
            let found = CalibreDiscoveredServer(name: sender.name, address: address)
            if !servers.contains(where: { $0.address == address }) {
                servers.append(found)
                servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    nonisolated func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in isSearching = false }
    }

    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        Task { @MainActor in isSearching = false }
    }
}

enum CalibreCredentials {
    private static let service = "app.getwoodwork.calibre"
    private static let account = "content-server-password"

    static func loadPassword() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func savePassword(_ password: String) {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(identity as CFDictionary)
        guard !password.isEmpty else { return }
        var item = identity
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
