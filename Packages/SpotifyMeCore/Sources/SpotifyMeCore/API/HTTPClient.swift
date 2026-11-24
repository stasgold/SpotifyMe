import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum APIError: Error, LocalizedError {
    case http(status: Int, body: String)
    case unauthorized
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .http(let status, let body): return "Request failed (\(status)): \(body.prefix(200))"
        case .unauthorized: return "Your Spotify session expired. Please sign in again."
        case .invalidResponse: return "Unexpected response from the server."
        }
    }
}

/// Small async HTTP helper with retry on 429 (rate limiting) and 5xx.
public struct HTTPClient: Sendable {
    public let session: URLSession
    public var maxRetries: Int

    public init(session: URLSession = .shared, maxRetries: Int = 3) {
        self.session = session
        self.maxRetries = maxRetries
    }

    public func send(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401:
                throw APIError.unauthorized
            case let status where (status == 429 || status >= 500) && attempt < maxRetries:
                attempt += 1
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? pow(2, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(min(retryAfter, 30) * 1_000_000_000))
            default:
                throw APIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
        }
    }

    public func get<T: Decodable>(_ url: URL, headers: [String: String] = [:], as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let data = try await send(request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension URL {
    /// Builds a URL from a base string and query items. The base must be a valid URL literal.
    static func make(_ base: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents(string: base)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }
}
