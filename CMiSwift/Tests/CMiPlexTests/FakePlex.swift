import Foundation
@testable import CMiPlex

/// Fakes plex.tv and media servers through a URLProtocol. Each instance owns the hosts `*.<id>.test`,
/// so tests can run in parallel.
final class FakePlex: @unchecked Sendable {
    enum Response {
        case json(String)
        case status(Int)
        case unreachable
    }

    let id = UUID().uuidString.lowercased()
    let supportFolder: URL
    let store: PlexStore
    private let lock = NSLock()
    private var routes: [String: Response] = [:]
    private var _requests: [URLRequest] = []

    init() {
        supportFolder = scratchFolder.appendingPathComponent(id)
        try! FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
        store = PlexStore(supportFolder: supportFolder)
        StubURLProtocol.register(self)
    }

    deinit {
        StubURLProtocol.unregister(self)
        try? FileManager.default.removeItem(at: supportFolder)
    }

    func host(_ name: String) -> String { "\(name).\(id).test" }

    var plexTV: URL { URL(string: "https://\(host("plextv"))")! }

    func url(_ name: String, port: Int = 32400) -> String { "http://\(host(name)):\(port)" }

    /// `url` is everything before the query, e.g. "https://plextv.<id>.test/api/v2/pins".
    func route(_ url: String, _ response: Response) {
        lock.withLock { routes[url] = response }
    }

    var requests: [URLRequest] { lock.withLock { _requests } }

    func requests(to path: String) -> [URLRequest] { requests.filter { $0.url?.path == path } }


    func makePlex() -> Plex {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return Plex(store: store, plexTV: plexTV, session: URLSession(configuration: configuration))
    }

    func signIn(serverURL: String, token: String = "server-token") throws {
        try store.signIn(url: serverURL, token: token, serverName: "Living room")
    }

    fileprivate func respond(to request: URLRequest) -> Response {
        var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        components.query = nil
        return lock.withLock {
            _requests.append(request)
            return routes[components.string!] ?? .status(404)
        }
    }
}

let scratchFolder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("scratch/CMiPlexTests")

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fakes: [String: FakePlex] = [:]

    static func register(_ fake: FakePlex) { lock.withLock { fakes[fake.id] = fake } }
    static func unregister(_ fake: FakePlex) { lock.withLock { fakes[fake.id] = nil } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Data(reading: stream)
        }
        let parts = request.url?.host?.split(separator: ".") ?? []
        let fake = parts.count >= 3 ? Self.lock.withLock { Self.fakes[String(parts[parts.count - 2])] } : nil
        switch fake?.respond(to: request) ?? .unreachable {
        case .unreachable:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        case .status(let code):
            send(code, Data())
        case .json(let json):
            send(200, Data(json.utf8))
        }
    }

    private func send(_ status: Int, _ data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}

extension URLRequest {
    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
