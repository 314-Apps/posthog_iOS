import Foundation

/// DRF's standard page envelope: `{count, next, previous, results}`.
public struct Paginated<Item: Decodable & Sendable>: Decodable, Sendable {
  public let count: Int?
  public let next: URL?
  public let previous: URL?
  public let results: [Item]
}

extension APIClient {
  /// Follows `next` URLs page by page. List screens consume this with a
  /// load-more sentinel row; it never fetches past what the caller iterates.
  public func pages<Item: Decodable & Sendable>(
    startingAt request: APIRequest,
    of type: Item.Type = Item.self
  ) -> AsyncThrowingStream<Paginated<Item>, Error> {
    let (stream, continuation) = AsyncThrowingStream<Paginated<Item>, Error>.makeStream()
    let client = self
    let task = Task {
      var pending: APIRequest? = request
      do {
        while let current = pending {
          let page: Paginated<Item> = try await client.send(current)
          continuation.yield(page)
          if let next = page.next, let components = URLComponents(url: next, resolvingAgainstBaseURL: false) {
            pending = APIRequest(
              method: .get,
              path: components.path,
              query: components.queryItems ?? []
            )
          } else {
            pending = nil
          }
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}
