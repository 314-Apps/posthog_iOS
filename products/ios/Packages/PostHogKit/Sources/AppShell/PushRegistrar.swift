import Foundation
import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import SwiftUI
import UserNotifications

/// Owns APNs registration: permission prompt, device-token upload, and the
/// once-only pre-permission state. The system prompt is never shown at first
/// launch; an awareness moment (opening the inbox) triggers the card instead.
@MainActor
public final class PushRegistrar {
  public static let shared = PushRegistrar()

  private var client: APIClient?
  private var pendingToken: String?
  private var registeredToken: String?

  private init() {}

  /// The signed-in session's client; a token that arrived early uploads now.
  public func configure(client: APIClient?) {
    self.client = client
    if let pendingToken {
      upload(pendingToken)
    }
  }

  /// Asks for notification permission and, when granted, registers with APNs.
  public func requestAuthorization() async -> Bool {
    do {
      let granted = try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .badge, .sound])
      if granted {
        UIApplication.shared.registerForRemoteNotifications()
      }
      return granted
    } catch {
      PHLog.auth.error("push authorization failed: \(error)")
      return false
    }
  }

  /// Called by the app delegate with the raw APNs token.
  public func handleDeviceToken(_ deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    guard token != registeredToken else { return }
    if client != nil {
      upload(token)
    } else {
      pendingToken = token
    }
  }

  /// Best-effort de-registration on sign-out.
  public func unregister() {
    guard let client, let token = registeredToken else { return }
    registeredToken = nil
    Task { try? await client.unregisterPushToken(token) }
  }

  private func upload(_ token: String) {
    guard let client else { return }
    pendingToken = nil
    Task {
      do {
        try await client.registerPushToken(token)
        registeredToken = token
        PHLog.auth.info("push token registered")
      } catch {
        PHLog.auth.error("push token registration failed: \(error)")
        pendingToken = token
      }
    }
  }
}

/// SwiftUI adaptor target for the remote-notification callbacks.
public final class PushAppDelegate: NSObject, UIApplicationDelegate {
  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task { @MainActor in
      PushRegistrar.shared.handleDeviceToken(deviceToken)
    }
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: any Error
  ) {
    PHLog.auth.error("APNs registration failed: \(error)")
  }
}

/// The awareness-moment card: explains what arrives before the system prompt.
public struct PushPrePermissionCard: View {
  @AppStorage("push.prompted") private var hasPrompted = false
  @State private var isRequesting = false

  public init() {}

  public var body: some View {
    if !hasPrompted {
      VStack(alignment: .leading, spacing: 12) {
        Text("Get notified when it matters")
          .font(.headline)
        Text("Alerts firing, mentions, and issues assigned to you. Nothing else.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Button {
          isRequesting = true
          Task {
            _ = await PushRegistrar.shared.requestAuthorization()
            hasPrompted = true
            isRequesting = false
          }
        } label: {
          Group {
            if isRequesting {
              ProgressView()
            } else {
              Text("Enable notifications")
            }
          }
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Color.white)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(PHColor.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
        Button("Not now") {
          hasPrompted = true
        }
        .font(.footnote.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 32)
      }
      .padding(PHSpacing.lg)
      .background(PHColor.surface, in: RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous)
          .strokeBorder(PHColor.border, lineWidth: 1)
      )
    }
  }
}
