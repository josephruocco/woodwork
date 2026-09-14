import Foundation

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

    func fetchBooks() async throws -> [Book] {
        let libraryInfo = try await json(path: "/ajax/library-info")
        guard let info = libraryInfo as? [String: Any],
              let libraryID = info["default_library"] as? String,
              !libraryID.isEmpty else {
            throw CalibreServerError.invalidResponse
        }

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
        return books
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
        try await json(url: baseURL.appending(path: path))
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
