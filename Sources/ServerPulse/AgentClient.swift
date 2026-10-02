import Foundation

protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionTransport: HTTPTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await Self.session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

protocol MetricsFetching: Sendable {
    /// Throws `MonitorError`, or `CancellationError` when the calling task was cancelled.
    func fetch(url: URL, token: String) async throws -> AgentSnapshot
}

struct AgentClient: MetricsFetching {
    var transport: HTTPTransport = URLSessionTransport()

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff
    ]

    func fetch(url: URL, token: String) async throws -> AgentSnapshot {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response: (data: Data, status: Int)
        do {
            response = try await transport.send(request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw MonitorError.offline
        } catch {
            throw MonitorError.unreachable
        }
        switch response.status {
        case 200: return try Self.decode(response.data)
        case 401: throw MonitorError.unauthorized
        default: throw MonitorError.http(response.status)
        }
    }

    static func decode(_ data: Data) throws -> AgentSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw MonitorError.decoding
        }
        guard let version = (root["version"] as? NSNumber)?.intValue, version >= 2 else {
            throw MonitorError.outdatedAgent
        }
        do {
            return try JSONDecoder().decode(AgentSnapshot.self, from: data)
        } catch {
            throw MonitorError.decoding
        }
    }
}
