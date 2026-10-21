import PostHogAPI
import PostHogDesignSystem
import SwiftUI

/// Sign-in: brand, region choice, one orange CTA. SSO/2FA happen in the
/// browser sheet — that is the point of OAuth here.
struct WelcomeView: View {
  @Environment(SessionStore.self) private var session

  @State private var region: Region = .us
  @State private var showingSelfHosted = false

  private var regions: [Region] {
    #if POSTHOG_DEV_REGION
      [.us, .eu, .dev]
    #else
      [.us, .eu]
    #endif
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      VStack(spacing: PHSpacing.lg) {
        Text("PostHog")
          .font(.system(size: 40, weight: .heavy))
          .foregroundStyle(Color(white: 0.95))
        Text("Check metrics, flip feature flags, and watch replays from anywhere.")
          .font(.body)
          .foregroundStyle(Color(white: 0.72))
          .multilineTextAlignment(.center)
          .frame(maxWidth: 300)
      }
      Spacer()
      VStack(spacing: PHSpacing.md) {
        HStack(spacing: PHSpacing.sm + 2) {
          ForEach(regions) { option in
            regionCard(option)
          }
        }
        Button {
          Task { await session.signIn(region: region) }
        } label: {
          Group {
            if session.isSigningIn {
              ProgressView().tint(.white)
            } else {
              Text("Continue")
            }
          }
          .font(.headline)
          .foregroundStyle(Color.white)
          .frame(maxWidth: .infinity, minHeight: 54)
          .background(PHColor.accent, in: RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(session.isSigningIn)
        if let error = session.signInError {
          Text(error)
            .font(.footnote)
            .foregroundStyle(PHColor.danger)
            .multilineTextAlignment(.center)
        }
        Button("Sign in with an API key") {
          showingSelfHosted = true
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color(white: 0.62))
        .frame(minHeight: 44)
      }
      .padding(.horizontal, PHSpacing.xl)
      .padding(.bottom, 32)
    }
    .sheet(isPresented: $showingSelfHosted) {
      APIKeySignInSheet(region: region)
        .presentationDetents([.medium, .large])
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      LinearGradient(
        colors: [Color(red: 0.086, green: 0.094, blue: 0.122), Color(red: 0.129, green: 0.141, blue: 0.169)],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  private func regionCard(_ option: Region) -> some View {
    Button {
      region = option
    } label: {
      VStack(spacing: 3) {
        Text(option.displayName)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color(white: region == option ? 0.95 : 0.72))
        Text(option.hostDescription)
          .font(.caption)
          .foregroundStyle(Color(white: 0.55))
      }
      .frame(maxWidth: .infinity, minHeight: 56)
      .background(
        region == option ? PHColor.accent.opacity(0.12) : Color.white.opacity(0.03),
        in: RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: PHRadius.control, style: .continuous)
          .strokeBorder(
            region == option ? PHColor.accent : Color.white.opacity(0.14),
            lineWidth: 1.5
          )
      )
    }
    .buttonStyle(.plain)
  }
}
