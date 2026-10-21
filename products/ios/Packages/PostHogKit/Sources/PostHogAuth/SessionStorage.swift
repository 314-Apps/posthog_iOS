import Foundation
import PostHogFoundation
import Security

/// Where the session blob lives. Production is the Keychain; tests and UI-test
/// scenarios use the in-memory store.
public protocol SessionStorage: Sendable {
  func load() -> StoredSession?
  func save(_ session: StoredSession)
  func clear()
}

/// One generic-password item holding the JSON session blob.
/// `AfterFirstUnlockThisDeviceOnly`: refresh must work on background wake, and
/// tokens must not ride iCloud Keychain to other devices.
public struct KeychainSessionStore: SessionStorage {
  private let service = "com.posthog.ios.session"
  // Namespaced so multi-account later becomes `session.<uuid>` with no migration.
  private let account = "session.default"

  public init() {}

  public func load() -> StoredSession? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      if status != errSecItemNotFound {
        PHLog.auth.error("keychain load failed: \(status)")
      }
      return nil
    }
    return try? JSONDecoder().decode(StoredSession.self, from: data)
  }

  public func save(_ session: StoredSession) {
    guard let data = try? JSONEncoder().encode(session) else { return }
    var query = baseQuery()
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      query.merge(attributes) { _, new in new }
      status = SecItemAdd(query as CFDictionary, nil)
    }
    if status != errSecSuccess {
      PHLog.auth.error("keychain save failed: \(status)")
    }
  }

  public func clear() {
    SecItemDelete(baseQuery() as CFDictionary)
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

/// Test/UI-test stand-in.
public final class InMemorySessionStore: SessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var session: StoredSession?

  public init(session: StoredSession? = nil) {
    self.session = session
  }

  public func load() -> StoredSession? {
    lock.withLock { session }
  }

  public func save(_ session: StoredSession) {
    lock.withLock { self.session = session }
  }

  public func clear() {
    lock.withLock { session = nil }
  }
}
