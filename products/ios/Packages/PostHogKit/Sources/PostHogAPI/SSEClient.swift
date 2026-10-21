import Foundation
import PostHogFoundation

/// One parsed server-sent event.
public struct ServerSentEvent: Sendable, Equatable {
  public var event: String?
  public var data: String
  public var id: String?
  public var retryMilliseconds: Int?

  public init(event: String? = nil, data: String, id: String? = nil, retryMilliseconds: Int? = nil) {
    self.event = event
    self.data = data
    self.id = id
    self.retryMilliseconds = retryMilliseconds
  }
}

/// Incremental SSE parser. Byte-level on purpose: the event delimiter is a blank
/// line, multi-line `data:` fields join with newlines, and `:` comment lines
/// (Max AI's 15s keepalives) must be dropped — line-based conveniences get the
/// edge cases wrong. Pure state machine, unit-tested without any network.
public struct SSEParser: Sendable {
  private var lineBuffer: [UInt8] = []
  private var eventName: String?
  private var dataLines: [String] = []
  private var lastID: String?
  private var retryMilliseconds: Int?

  public init() {}

  /// Feeds one byte; returns a completed event when this byte finishes one.
  public mutating func feed(_ byte: UInt8) -> ServerSentEvent? {
    if byte == 0x0A {  // \n
      var line = lineBuffer
      lineBuffer.removeAll(keepingCapacity: true)
      if line.last == 0x0D {  // trailing \r from CRLF
        line.removeLast()
      }
      return processLine(String(bytes: line, encoding: .utf8) ?? "")
    }
    lineBuffer.append(byte)
    return nil
  }

  private mutating func processLine(_ line: String) -> ServerSentEvent? {
    if line.isEmpty {
      return flush()
    }
    if line.hasPrefix(":") {  // comment / keepalive
      return nil
    }
    let field: Substring
    let value: Substring
    if let colon = line.firstIndex(of: ":") {
      field = line[..<colon]
      var rest = line[line.index(after: colon)...]
      if rest.hasPrefix(" ") { rest = rest.dropFirst() }
      value = rest
    } else {
      field = line[...]
      value = ""
    }
    switch field {
    case "event":
      eventName = String(value)
    case "data":
      dataLines.append(String(value))
    case "id":
      lastID = String(value)
    case "retry":
      retryMilliseconds = Int(value)
    default:
      break  // unknown fields are ignored per spec
    }
    return nil
  }

  private mutating func flush() -> ServerSentEvent? {
    defer {
      eventName = nil
      dataLines = []
    }
    guard !dataLines.isEmpty else { return nil }
    return ServerSentEvent(
      event: eventName,
      data: dataLines.joined(separator: "\n"),
      id: lastID,
      retryMilliseconds: retryMilliseconds
    )
  }
}

/// Streams server-sent events from a URL. Reconnection policy belongs to the
/// caller (livestream reconnects with Last-Event-ID; Max AI never reconnects).
public struct SSEClient: Sendable {
  private let session: URLSession

  public init(session: URLSession = SSEClient.makeSession()) {
    self.session = session
  }

  /// A session tuned for long-lived streams: 15s keepalives make a 90s request
  /// timeout safe, and the resource timeout must never fire mid-stream.
  public static func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 90
    configuration.timeoutIntervalForResource = .greatestFiniteMagnitude
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }

  public func events(
    url: URL,
    headers: [String: String] = [:],
    method: String = "GET",
    body: Data? = nil,
    lastEventID: String? = nil
  ) -> AsyncThrowingStream<ServerSentEvent, Error> {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if let lastEventID {
      request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID")
    }
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }

    let (stream, continuation) = AsyncThrowingStream<ServerSentEvent, Error>.makeStream()
    let session = self.session
    let task = Task {
      do {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
          throw APIError.network(underlying: URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
          throw APIError.server(status: http.statusCode, code: nil, detail: nil, attr: nil)
        }
        var parser = SSEParser()
        for try await byte in bytes {
          if let event = parser.feed(byte) {
            continuation.yield(event)
          }
        }
        continuation.finish()
      } catch is CancellationError {
        continuation.finish()
      } catch let error as URLError where error.code == .cancelled {
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}
