import Foundation
import PostHogAPI
import PostHogFoundation

/// How hard a run pushes past caches. Cellular-friendly defaults: dashboards
/// paint from cache then refresh with `lazyAsync`.
public enum RefreshMode: String, Sendable {
  case blocking
  case async
  case lazyAsync = "lazy_async"
  case forceBlocking = "force_blocking"
  case forceCache = "force_cache"
}

/// The async envelope: POST may return `{query_status}` instead of results.
struct QueryStatus: Sendable {
  let id: String?
  let complete: Bool
  let errorMessage: String?
  let results: JSONValue?

  init?(raw: JSONValue) {
    guard let status = raw["query_status"], status.objectValue != nil else { return nil }
    self.id = status["id"]?.stringValue
    self.complete = status["complete"]?.boolValue ?? false
    self.errorMessage = status["error_message"]?.stringValue
    self.results = status["results"]
  }
}

public enum QueryRunnerError: Error, Sendable {
  case queryFailed(message: String)
  case pollTimedOut
}

/// Executes queries against `/api/projects/{id}/query/`, following the async
/// envelope with capped-backoff polling. Cancellation cancels server-side too.
public struct QueryRunner: Sendable {
  private let client: APIClient
  private let pollCap: Duration
  private let maxPolls: Int

  public init(client: APIClient, pollCap: Duration = .seconds(3), maxPolls: Int = 120) {
    self.client = client
    self.pollCap = pollCap
    self.maxPolls = maxPolls
  }

  /// Runs a query and returns its parsed result.
  public func run(
    _ query: DataQuery,
    projectID: Int,
    refresh: RefreshMode = .blocking
  ) async throws -> QueryResult {
    let body: JSONValue = [
      "query": query.raw,
      "refresh": .string(refresh.rawValue),
      "client_query_id": .string("ios-\(UUID().uuidString.lowercased())"),
    ]
    let data = try await client.sendRaw(
      .post("/api/projects/\(projectID)/query/", body: APIClient.makeEncoder().encode(body))
    )
    let raw = try decodeJSON(data)

    if let status = QueryStatus(raw: raw) {
      if status.complete {
        return parse(query, from: status.results ?? .null)
      }
      guard let id = status.id else {
        throw QueryRunnerError.queryFailed(message: status.errorMessage ?? "missing query id")
      }
      return try await poll(query, projectID: projectID, queryID: id)
    }
    return parse(query, from: raw)
  }

  private func poll(_ query: DataQuery, projectID: Int, queryID: String) async throws -> QueryResult {
    let path = "/api/projects/\(projectID)/query/\(queryID)/"
    var delay: Duration = .milliseconds(500)
    for _ in 0..<maxPolls {
      do {
        try await Task.sleep(for: delay)
      } catch {
        // Cancelled while waiting — tell the server to stop, then bail out.
        Task { [client] in try? await client.sendRaw(.delete(path)) }
        throw APIError.cancelled
      }
      delay = min(delay * 3 / 2, pollCap)

      let data = try await client.sendRaw(.get(path))
      let raw = try decodeJSON(data)
      guard let status = QueryStatus(raw: raw) else {
        return parse(query, from: raw)
      }
      if let message = status.errorMessage, !message.isEmpty {
        throw QueryRunnerError.queryFailed(message: message)
      }
      if status.complete {
        return parse(query, from: status.results ?? .null)
      }
    }
    throw QueryRunnerError.pollTimedOut
  }

  private func parse(_ query: DataQuery, from body: JSONValue) -> QueryResult {
    QueryResult.parse(kind: query.renderSource.kind, body: body)
  }

  private func decodeJSON(_ data: Data) throws -> JSONValue {
    do {
      return try JSONDecoder().decode(JSONValue.self, from: data)
    } catch {
      throw APIError.decoding(underlying: error)
    }
  }
}
