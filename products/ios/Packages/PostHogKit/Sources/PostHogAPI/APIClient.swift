import Foundation
import PostHogFoundation

/// The one HTTP door to a PostHog instance.
///
/// Owns auth injection, the retry ladder (401 → one forced refresh; 429 → honor
/// Retry-After once; transient GET errors → one retry), and DRF error parsing.
/// Endpoint methods live in extensions under `Endpoints/`.
public struct APIClient: Sendable {
  public let baseURL: URL
  let transport: HTTPTransport
  let tokens: TokenProviding?
  let clientInfo: ClientInfo

  /// PostHog and DRF speak different casing dialects (REST is snake_case, the
  /// query schema is camelCase), so models declare CodingKeys explicitly and the
  /// coders apply no key strategy.
  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom(Self.decodeISO8601)
    return decoder
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  public init(
    baseURL: URL,
    transport: HTTPTransport = URLSessionTransport(),
    tokens: TokenProviding?,
    clientInfo: ClientInfo = .current
  ) {
    self.baseURL = baseURL
    self.transport = transport
    self.tokens = tokens
    self.clientInfo = clientInfo
  }

  // MARK: Sending

  public func send<Response: Decodable & Sendable>(
    _ request: APIRequest,
    as type: Response.Type = Response.self
  ) async throws -> Response {
    let data = try await sendRaw(request)
    do {
      return try Self.makeDecoder().decode(Response.self, from: data)
    } catch {
      PHLog.api.error("decode failed for \(request.path, privacy: .public): \(error)")
      throw APIError.decoding(underlying: error)
    }
  }

  /// Sends and returns the raw body. 204/205 responses return empty data.
  @discardableResult
  public func sendRaw(_ request: APIRequest) async throws -> Data {
    var attempt = 0
    var freshToken: String?
    while true {
      attempt += 1
      let urlRequest = try await buildURLRequest(for: request, overrideToken: freshToken)
      let (data, response): (Data, HTTPURLResponse)
      do {
        (data, response) = try await transport.send(urlRequest)
      } catch let error as URLError {
        if error.code == .cancelled { throw APIError.cancelled }
        let wrapped = APIError.network(underlying: error)
        if request.method == .get, attempt == 1, wrapped.isRetriableTransport {
          continue
        }
        throw wrapped
      } catch is CancellationError {
        throw APIError.cancelled
      }

      switch response.statusCode {
      case 200..<300:
        return data
      case 401 where request.authorization == .bearer && attempt == 1:
        freshToken = try await forceRefresh()
        continue
      case 401,
        403 where isAuthenticationFailure(data):
        throw APIError.unauthorized
      case 429 where attempt == 1:
        let delay = retryAfter(response) ?? 1
        try await Task.sleep(for: .seconds(min(delay, 10)))
        continue
      case 429:
        throw APIError.rateLimited(retryAfter: retryAfter(response))
      default:
        throw Self.serverError(status: response.statusCode, data: data)
      }
    }
  }

  // MARK: Internals

  func buildURLRequest(for request: APIRequest, overrideToken: String?) async throws -> URLRequest {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw APIError.network(underlying: URLError(.badURL))
    }
    components.path = request.path
    if !request.query.isEmpty {
      components.queryItems = request.query
    }
    guard let url = components.url else {
      throw APIError.network(underlying: URLError(.badURL))
    }

    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = request.method.rawValue
    urlRequest.httpBody = request.body
    urlRequest.setValue(clientInfo.userAgent, forHTTPHeaderField: "User-Agent")
    urlRequest.setValue(clientInfo.clientHeader, forHTTPHeaderField: "x-posthog-client")
    if request.body != nil {
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    if request.authorization == .bearer {
      guard let tokens else {
        throw APIError.unauthorized
      }
      let token: String
      if let overrideToken {
        token = overrideToken
      } else {
        do {
          token = try await tokens.validAccessToken()
        } catch let error as TokenRefreshError {
          if case .authFailure = error {
            throw APIError.unauthorized
          }
          throw APIError.network(underlying: URLError(.userAuthenticationRequired))
        }
      }
      urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return urlRequest
  }

  private func forceRefresh() async throws -> String {
    guard let tokens else { throw APIError.unauthorized }
    do {
      return try await tokens.refreshedAccessToken()
    } catch let error as TokenRefreshError {
      if case .authFailure = error {
        throw APIError.unauthorized
      }
      throw APIError.network(underlying: URLError(.userAuthenticationRequired))
    }
  }

  /// 403 signs the user out only for real credential failures — permission
  /// errors on a resource must not kill the session.
  private func isAuthenticationFailure(_ data: Data) -> Bool {
    guard let body = try? JSONDecoder().decode(DRFErrorBody.self, from: data) else {
      return false
    }
    return body.code == "authentication_failed" || body.code == "not_authenticated"
  }

  private func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
    response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
  }

  static func serverError(status: Int, data: Data) -> APIError {
    let body = try? JSONDecoder().decode(DRFErrorBody.self, from: data)
    return .server(status: status, code: body?.code, detail: body?.detail, attr: body?.attr)
  }

  /// PostHog timestamps come with and without fractional seconds.
  private static func decodeISO8601(_ decoder: Decoder) throws -> Date {
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    if let date = try? Date(string, strategy: fractional) {
      return date
    }
    if let date = try? Date(string, strategy: .iso8601) {
      return date
    }
    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Unrecognized ISO 8601 date: \(string)"
    )
  }
}

/// DRF's standard error body: `{"type": ..., "code": ..., "detail": ..., "attr": ...}`.
struct DRFErrorBody: Decodable {
  let type: String?
  let code: String?
  let detail: String?
  let attr: String?
}

/// Identifies this client to the backend.
public struct ClientInfo: Sendable {
  public let appVersion: String
  public let buildNumber: String

  public var userAgent: String { "PostHogiOS/\(appVersion) (build \(buildNumber))" }
  public var clientHeader: String { "posthog-ios-app/\(appVersion)" }

  public init(appVersion: String, buildNumber: String) {
    self.appVersion = appVersion
    self.buildNumber = buildNumber
  }

  public static let current: ClientInfo = {
    let info = Bundle.main.infoDictionary
    return ClientInfo(
      appVersion: info?["CFBundleShortVersionString"] as? String ?? "0.0.0",
      buildNumber: info?["CFBundleVersion"] as? String ?? "0"
    )
  }()
}
