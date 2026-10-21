import PostHogAPI
import PostHogDesignSystem
import SwiftUI

/// First-run project selection (org-wide grants), and the switcher sheet.
struct ProjectPickerView: View {
  @Environment(SessionStore.self) private var session

  let onSelect: (Int) -> Void

  var body: some View {
    Group {
      if session.availableProjects.isEmpty {
        VStack(spacing: PHSpacing.lg) {
          ForEach(0..<4, id: \.self) { _ in
            SkeletonView(cornerRadius: PHRadius.control).frame(height: 52)
          }
          Spacer()
        }
        .padding(PHSpacing.lg)
      } else {
        List {
          ForEach(groupedProjects, id: \.0) { organizationName, projects in
            Section(organizationName) {
              ForEach(projects) { project in
                Button {
                  onSelect(project.id)
                } label: {
                  HStack {
                    Text(project.name)
                      .font(.body.weight(.semibold))
                      .foregroundStyle(PHColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.bold))
                      .foregroundStyle(PHColor.textTertiary)
                  }
                  .frame(minHeight: 44)
                }
              }
            }
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
      }
    }
    .background(PHColor.background)
    .navigationTitle("Choose a project")
    .task { await session.loadProjects() }
  }

  private var groupedProjects: [(String, [Project])] {
    let organizations = Dictionary(
      uniqueKeysWithValues: (session.user?.organizations ?? []).map { ($0.id, $0.name) }
    )
    let grouped = Dictionary(grouping: session.availableProjects) { project in
      project.organizationID.flatMap { organizations[$0] } ?? "Projects"
    }
    return grouped.sorted { $0.key < $1.key }
  }
}
