import Foundation
import PostHogAPI

/// Canned-response transport shared by every test target. Each call consumes
/// the next scripted result; requests are recorded for assertions.
public final class StubTransport: HTTPTransport, @unchecked Sendable {
  public enum Scripted {
    case response(status: Int, body: Data, headers: [String: String] = [:])
    case error(URLError)
    /// Delays before responding — for single-flight concurrency tests.
    case slowResponse(status: Int, body: Data, delay: TimeInterval)
  }

  private let lock = NSLock()
  private var script: [Scripted]
  private var recorded: [URLRequest] = []

  public var requests: [URLRequest] { lock.withLock { recorded } }
  public var callCount: Int { lock.withLock { recorded.count } }

  public init(script: [Scripted]) {
    self.script = script
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let next: Scripted? = lock.withLock {
      recorded.append(request)
      return script.isEmpty ? nil : script.removeFirst()
    }
    switch next {
    case .none:
      fatalError("StubTransport script exhausted for \(request.url?.absoluteString ?? "?")")
    case .error(let error):
      throw error
    case .response(let status, let body, let headers):
      return (body, makeResponse(request, status: status, headers: headers))
    case .slowResponse(let status, let body, let delay):
      try await Task.sleep(for: .seconds(delay))
      return (body, makeResponse(request, status: status, headers: [:]))
    }
  }

  private func makeResponse(
    _ request: URLRequest,
    status: Int,
    headers: [String: String]
  ) -> HTTPURLResponse {
    HTTPURLResponse(
      url: request.url!,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    )!
  }
}

/// TokenProviding stub with counters.
public final class StubTokens: TokenProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var validCount = 0
  private var refreshCount = 0

  public var validResult: Result<String, TokenRefreshError> = .success("pha_valid")
  public var refreshResult: Result<String, TokenRefreshError> = .success("pha_refreshed")

  public var validCalls: Int { lock.withLock { validCount } }
  public var refreshCalls: Int { lock.withLock { refreshCount } }

  public init() {}

  public func validAccessToken() async throws -> String {
    lock.withLock { validCount += 1 }
    return try validResult.get()
  }

  public func refreshedAccessToken() async throws -> String {
    lock.withLock { refreshCount += 1 }
    return try refreshResult.get()
  }
}
