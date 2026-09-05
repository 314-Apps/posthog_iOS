import PostHogDesignSystem
import SwiftUI

/// The app's root: switches between sign-in, project pick, and the tab shell.
public struct RootView: View {
  @Environment(SessionStore.self) private var session

  public init() {}

  public var body: some View {
    Group {
      switch session.phase {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(PHColor.background)
      case .signedOut:
        WelcomeView()
      case .needsProject:
        NavigationStack {
          ProjectPickerView { projectID in
            Task { await session.selectProject(projectID) }
          }
        }
      case .signedIn(let context):
        SignedInShell(context: context)
          .id(context.projectID)
      }
    }
    .task { await session.bootstrap() }
  }
}
