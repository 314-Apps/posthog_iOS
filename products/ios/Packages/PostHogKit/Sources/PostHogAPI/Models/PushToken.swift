import Foundation
import PostHogFoundation

extension APIClient {
  /// Registers this device's APNs token for the signed-in user.
  public func registerPushToken(_ token: String) async throws {
    let body: JSONValue = [
      "token": .string(token),
      "platform": "ios",
      "provider": "apns",
    ]
    try await sendRaw(
      .post("/api/users/@me/push_tokens/", body: Self.makeEncoder().encode(body))
    )
  }

  public func unregisterPushToken(_ token: String) async throws {
    let body: JSONValue = ["token": .string(token)]
    try await sendRaw(
      .post("/api/users/@me/push_tokens/unregister/", body: Self.makeEncoder().encode(body))
    )
  }
}
