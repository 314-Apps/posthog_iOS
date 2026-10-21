import PostHogAPI
import PostHogDesignSystem
import SwiftUI

/// Sign-in with a personal API key. This works against any instance, cloud or
/// self-hosted: OAuth needs a client registered for this app on the instance,
/// and an API key needs nothing but the key.
struct APIKeySignInSheet: View {
  @Environment(SessionStore.self) private var session
  @Environment(\.dismiss) private var dismiss

  @State private var urlText: String
  @State private var apiKey = ""

  init(region: Region) {
    self._urlText = State(initialValue: region.apiBaseURL.absoluteString)
  }

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

  private var keySettingsURL: URL? {
    parsedURL?.appending(path: "/settings/user-api-keys")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("https://us.posthog.com", text: $urlText)
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
            "Create a key under settings, personal API keys, and give it access to the "
              + "projects and scopes you want to use. The key is checked before it is saved."
          )
        }
        if let keySettingsURL {
          Section {
            Link(destination: keySettingsURL) {
              HStack {
                Text("Create a personal API key")
                Spacer()
                Image(systemName: "arrow.up.right.square")
                  .foregroundStyle(PHColor.textTertiary)
              }
              .frame(minHeight: 32)
            }
          }
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
      .navigationTitle("Sign in with a key")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}
