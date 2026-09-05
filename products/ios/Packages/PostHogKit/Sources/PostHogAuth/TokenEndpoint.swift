import Foundation
import PostHogAPI

/// `/oauth/token/` response. Rotating refresh: every grant returns a new pair.
struct TokenResponse: Decodable, Sendable {
  let accessToken: String
  let refreshToken: String
  let expiresIn: TimeInterval
  let scopedTeams: [Int]?
  let scopedOrganizations: [String]?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case scopedTeams = "scoped_teams"
    case scopedOrganizations = "scoped_organizations"
  }
}

/// `/oauth/token/` error body — `error` drives the refresh taxonomy.
struct OAuthErrorBody: Decodable, Sendable {
  let error: String?
  let errorDescription: String?

  enum CodingKeys: String, CodingKey {
    case error
    case errorDescription = "error_description"
  }
}

enum TokenEndpoint {
  /// application/x-www-form-urlencoded body.
  static func formBody(_ fields: [(String, String)]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let encoded = fields.map { key, value in
      let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
      let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
      return "\(encodedKey)=\(encodedValue)"
    }
    return Data(encoded.joined(separator: "&").utf8)
  }

  static func makeRequest(url: URL, fields: [(String, String)]) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = formBody(fields)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  /// The load-bearing taxonomy, ported from the RN app's oauth.ts: only 401/403
  /// or a 400 whose `error` is invalid_grant/invalid_token means the session is
  /// dead. Other 400s (invalid_client…) are config bugs — signing the user out
  /// on those would strand them permanently.
  static func classifyFailure(status: Int, body: Data) -> TokenRefreshError {
    if status == 401 || status == 403 {
      return .authFailure(detail: "http_\(status)")
    }
    if status == 400 {
      let parsed = try? JSONDecoder().decode(OAuthErrorBody.self, from: body)
      if let error = parsed?.error, error == "invalid_grant" || error == "invalid_token" {
        return .authFailure(detail: error)
      }
      return .unknown(detail: parsed?.error ?? "http_400")
    }
    if (500..<600).contains(status) {
      return .serverError(status: status)
    }
    return .unknown(detail: "http_\(status)")
  }
}
