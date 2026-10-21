import Foundation

public enum HTTPMethod: String, Sendable {
  case get = "GET"
  case post = "POST"
  case patch = "PATCH"
  case delete = "DELETE"
}

/// How a request authenticates. `.bearer` is the default for every product API;
/// `.none` is for endpoints reachable before sign-in.
public enum AuthorizationMode: Sendable {
  case bearer
  case none
}

/// One API call: path, method, query, body. Bodies are pre-encoded so callers
/// control the encoder (queries must round-trip `JSONValue` fields untouched).
public struct APIRequest: Sendable {
  public var method: HTTPMethod
  public var path: String
  public var query: [URLQueryItem]
  public var body: Data?
  public var authorization: AuthorizationMode

  public init(
    method: HTTPMethod,
    path: String,
    query: [URLQueryItem] = [],
    body: Data? = nil,
    authorization: AuthorizationMode = .bearer
  ) {
    self.method = method
    self.path = path
    self.query = query
    self.body = body
    self.authorization = authorization
  }

  public static func get(_ path: String, query: [URLQueryItem] = []) -> APIRequest {
    APIRequest(method: .get, path: path, query: query)
  }

  public static func post(_ path: String, body: Data? = nil) -> APIRequest {
    APIRequest(method: .post, path: path, body: body)
  }

  public static func patch(_ path: String, body: Data) -> APIRequest {
    APIRequest(method: .patch, path: path, body: body)
  }

  public static func delete(_ path: String) -> APIRequest {
    APIRequest(method: .delete, path: path)
  }
}
