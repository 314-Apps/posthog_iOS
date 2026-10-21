import CryptoKit
import Foundation

/// RFC 7636 code verifier + S256 challenge. The server accepts S256 only.
public struct PKCEPair: Sendable, Equatable {
  public let verifier: String
  public let challenge: String

  public init() {
    var bytes = [UInt8](repeating: 0, count: 64)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    self.init(verifierBytes: Data(bytes))
  }

  init(verifierBytes: Data) {
    let verifier = PKCEPair.base64URLEncode(verifierBytes)
    self.verifier = verifier
    self.challenge = PKCEPair.challenge(for: verifier)
  }

  /// Test seam: challenge for a known verifier (RFC 7636 appendix B).
  public static func challenge(for verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return base64URLEncode(Data(digest))
  }

  static func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
