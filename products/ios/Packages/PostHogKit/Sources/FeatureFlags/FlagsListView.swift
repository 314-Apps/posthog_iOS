import PostHogAPI
import PostHogDesignSystem
import PostHogQueries
import SwiftUI

/// Flags root. No inline toggles — accidental production toggles from a list
/// scroll are the nightmare; the row opens detail, where toggling confirms.
public struct FlagsListView: View {
  enum StatusFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case inactive = "Inactive"
  }

  @State private var model: FlagsListModel

  private let onOpen: (Int) -> Void

  public init(context: ProjectContext, onOpen: @escaping (Int) -> Void) {
    self._model = State(initialValue: FlagsListModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    Group {
      switch model.state {
      case .loading:
        List {
          ForEach(0..<8, id: \.self) { _ in
            SkeletonView(cornerRadius: 10).frame(height: 40).listRowBackground(Color.clear)
          }
        }
        .listStyle(.plain)
      case .failed(let message):
        EmptyStateView(
          systemImage: "wifi.exclamationmark",
          title: "Couldn't load flags",
          message: message,
          actionTitle: "Retry"
        ) {
          Task { await model.load(forceRefresh: true) }
        }
      case .loaded where model.filtered.isEmpty:
        EmptyStateView(
          systemImage: "flag",
          title: "No flags here",
          message: "Feature flags you create show up here."
        )
      case .loaded:
        List(model.filtered) { flag in
          row(flag)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(forceRefresh: true) }
      }
    }
    .background(PHColor.background)
    .searchable(text: $model.search, prompt: "Search by key")
    .navigationTitle("Flags")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Picker("Status", selection: $model.status) {
          ForEach(StatusFilter.allCases, id: \.self) { status in
            Text(status.rawValue).tag(status)
          }
        }
        .pickerStyle(.menu)
      }
    }
    .task { await model.load() }
  }

  private func row(_ flag: FeatureFlag) -> some View {
    Button {
      onOpen(flag.id)
    } label: {
      HStack(spacing: PHSpacing.md) {
        Circle()
          .fill(flag.active ? PHColor.successFill : PHColor.textInactive.opacity(0.4))
          .frame(width: 9, height: 9)
        VStack(alignment: .leading, spacing: 2) {
          Text(flag.key)
            .font(PHFont.mono(14))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          Text(flag.rolloutSummary)
            .font(.caption)
            .foregroundStyle(PHColor.textSecondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(PHColor.textTertiary)
      }
      .frame(minHeight: 44)
    }
  }
}

@MainActor
@Observable
final class FlagsListModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var flags: [FeatureFlag] = []
  var search = ""
  var status: FlagsListView.StatusFilter = .all

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  var filtered: [FeatureFlag] {
    flags.filter { flag in
      if flag.deleted { return false }
      switch status {
      case .all: break
      case .active: if !flag.active { return false }
      case .inactive: if flag.active { return false }
      }
      guard !search.isEmpty else { return true }
      return flag.key.localizedCaseInsensitiveContains(search)
        || flag.name.localizedCaseInsensitiveContains(search)
    }
  }

  func load(forceRefresh: Bool = false) async {
    let key = context.cacheKey("flags-list")
    if !forceRefresh, flags.isEmpty {
      if let hit = await context.cache.read(key, as: [FeatureFlag].self, staleAfter: 120) {
        flags = hit.value
        state = .loaded
        if !hit.isStale { return }
      }
    }
    do {
      let page = try await context.client.featureFlags(projectID: context.projectID)
      flags = page.results
      state = .loaded
      await context.cache.write(key, value: flags)
    } catch {
      if flags.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }
}
