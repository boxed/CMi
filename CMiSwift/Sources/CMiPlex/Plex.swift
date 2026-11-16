import Foundation

/// Talks to plex.tv (sign in, server discovery) and to the signed in media server (library, progress).
public actor Plex {
    public let store: PlexStore
    let plexTV: URL
    let session: URLSession
    var lastReconnect: Date?

    static let timeout: TimeInterval = 10
    static let probeTimeout: TimeInterval = 3

    public init(store: PlexStore, plexTV: URL = URL(string: "https://plex.tv")!, session: URLSession = .shared) {
        self.store = store
        self.plexTV = plexTV
        self.session = session
    }

    public var isSignedIn: Bool { store.isSignedIn }
    public var serverName: String? { store.serverName }

    public func signOut() {
        try? store.signOut()
    }

    // MARK: - Requests

    func headers() throws -> [String: String] {
        [
            "X-Plex-Product": "CMi",
            "X-Plex-Device-Name": "CMi",
            "X-Plex-Client-Identifier": try store.clientID(),
            "Accept": "application/json",
        ]
    }

    func request(_ url: URL, token: String? = nil, method: String = "GET", timeout: TimeInterval = Plex.timeout) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        for (name, value) in try headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }
        return request
    }

    func plexTVURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        url(base: plexTV.absoluteString, path: path, query: query)
    }

    func url(base: String, path: String, query: [URLQueryItem] = []) -> URL {
        var base = base
        while base.hasSuffix("/") { base.removeLast() }
        var components = URLComponents(string: base + path)!
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        return components.url!
    }

    /// Fetches the data, throwing PlexError.httpStatus for anything but 2xx.
    func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlexError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw PlexError.httpStatus(http.statusCode) }
        return data
    }

    /// The error's message, plus which host failed and the TLS error code for failed secure connections,
    /// e.g. "A TLS error caused the secure connection to fail. (plex.tv, -9813)".
    public static func describe(_ error: Error) -> String {
        let error = error as NSError
        var details: [String] = []
        if let host = (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host { details.append(host) }
        if let code = error.userInfo["_kCFStreamErrorCodeKey"] as? Int, code != 0 { details.append(String(code)) }
        return details.isEmpty ? error.localizedDescription : "\(error.localizedDescription) (\(details.joined(separator: ", ")))"
    }

    func decode<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
        let data = try await data(for: request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PlexError.invalidResponse
        }
    }
}
