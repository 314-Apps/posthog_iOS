import Foundation

/// The one error type API callers see.
public enum APIError: Error, Sendable {
  case network(underlying: URLError)
  /// A non-2xx response with DRF's `{type, code, detail, attr}` body when parseable.
  case server(status: Int, code: String?, detail: String?, attr: String?)
  /// 401 that survived a forced refresh — the session is dead.
  case unauthorized
  case rateLimited(retryAfter: TimeInterval?)
  case decoding(underlying: any Error)
  case cancelled
}

extension APIError {
  public var isRetriableTransport: Bool {
    if case .network(let underlying) = self {
      switch underlying.code {
      case .timedOut, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
        return true
      default:
        return false
      }
    }
    return false
  }
}
