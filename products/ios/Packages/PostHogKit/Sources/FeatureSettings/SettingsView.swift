import PostHogAPI
import PostHogDesignSystem
import SwiftUI

/// Account, instance, and sign-out. Reached from the profile button on Home —
/// there is deliberately no Settings tab.
public struct SettingsView<BillingDestination: View>: View {
  private let email: String?
  private let regionName: String
  private let appVersion: String
  private let billingDestination: () -> BillingDestination
  private let onSignOut: () -> Void

  @State private var confirmingSignOut = false
  @AppStorage("tab.slot3") private var slot3 = "flags"

  public init(
    email: String?,
    regionName: String,
    @ViewBuilder billingDestination: @escaping () -> BillingDestination,
    onSignOut: @escaping () -> Void
  ) {
    self.email = email
    self.regionName = regionName
    self.appVersion =
      (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    self.billingDestination = billingDestination
    self.onSignOut = onSignOut
  }

  public var body: some View {
    List {
      Section("Account") {
        LabeledContent("Email", value: email ?? "–")
        LabeledContent("Instance", value: regionName)
        NavigationLink("Billing and usage") {
          billingDestination()
        }
      }
      Section {
        Picker("Third tab", selection: $slot3) {
          Text("Flags").tag("flags")
          Text("Errors").tag("errors")
          Text("Replay").tag("replay")
          Text("Web analytics").tag("web")
        }
      } footer: {
        Text("Choose which product sits in the tab bar's third slot.")
      }
      Section {
        Button(role: .destructive) {
          confirmingSignOut = true
        } label: {
          Text("Sign out")
            .frame(minHeight: 32)
        }
      }
      Section {
        LabeledContent("Version", value: appVersion)
      } footer: {
        Text("Made by PostHog")
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(PHColor.background)
    .navigationTitle("Settings")
    .confirmationDialog("Sign out of PostHog?", isPresented: $confirmingSignOut) {
      Button("Sign out", role: .destructive) { onSignOut() }
      Button("Cancel", role: .cancel) {}
    }
  }
}
