import PostHogAPI
import PostHogDesignSystem
import SwiftUI

/// Self-hosted sign-in: instance URL + personal API key. OAuth apps can't be
/// pre-registered on arbitrary instances, so a scoped personal API key is the
/// supported credential there.
struct SelfHostedSheet: View {
  @Environment(SessionStore.self) private var session
  @Environment(\.dismiss) private var dismiss

  @State private var urlText = "https://"
  @State private var apiKey = ""

  private var parsedURL: URL? {
    guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)),
      let scheme = url.scheme, ["https", "http"].contains(scheme),
      url.host() != nil
    else { return nil }
    return url
  }

  private var canConnect: Bool {
    parsedURL != nil && apiKey.hasPrefix("phx_") && !session.isSigningIn
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("https://posthog.example.com", text: $urlText)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          SecureField("Personal API key (phx_…)", text: $apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Instance")
        } footer: {
          Text(
            "Create a personal API key under settings, personal API keys on your instance. "
              + "Scope it to the projects this app should reach."
          )
        }
        if let error = session.signInError {
          Section {
            Text(error)
              .font(.footnote)
              .foregroundStyle(PHColor.danger)
          }
        }
        Section {
          Button {
            guard let url = parsedURL else { return }
            Task {
              await session.signInSelfHosted(host: url, apiKey: apiKey)
              if session.signInError == nil {
                dismiss()
              }
            }
          } label: {
            HStack {
              Spacer()
              if session.isSigningIn {
                ProgressView()
              } else {
                Text("Connect")
              }
              Spacer()
            }
            .frame(minHeight: 32)
          }
          .disabled(!canConnect)
        }
      }
      .navigationTitle("Self-hosted")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}
