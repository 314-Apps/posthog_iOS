import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// The people behind one number. Opens from any metric a person can tap.
/// Routing to the person screen belongs to the caller, through `onOpenPerson`.
public struct ActorsSheet: View {
  @State private var model: ActorsSheetModel
  @State private var showingProvenance = false
  @Environment(\.dismiss) private var dismiss

  private let title: String
  private let onOpenPerson: (String) -> Void

  public init(
    context: ProjectContext,
    source: DataQuery,
    drill: ActorsDrill,
    title: String,
    onOpenPerson: @escaping (String) -> Void
  ) {
    self._model = State(
      initialValue: ActorsSheetModel(context: context, source: source, drill: drill)
    )
    self.title = title
    self.onOpenPerson = onOpenPerson
  }

  public var body: some View {
    NavigationStack {
      content
        .background(PHColor.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.search, prompt: "Search by email or ID")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingProvenance) {
          QueryProvenanceSheet(query: model.source, hogql: model.hogql)
        }
        .task { await model.loadFirstPage() }
        .task(id: model.search) {
          try? await Task.sleep(for: .milliseconds(350))
          guard !Task.isCancelled else { return }
          await model.loadFirstPage()
        }
    }
  }

  @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("Done") { dismiss() }
    }
    ToolbarItem(placement: .primaryAction) {
      Button {
        showingProvenance = true
      } label: {
        Image(systemName: "info.circle")
      }
      .accessibilityLabel("Where this data comes from")
    }
  }

  @ViewBuilder private var content: some View {
    if !model.rows.isEmpty {
      rowList
    } else if model.isLoading {
      skeletonList
    } else if model.errorText != nil {
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load these people",
        message: "Check your connection and try again.",
        actionTitle: "Retry"
      ) {
        Task { await model.reload() }
      }
    } else {
      EmptyStateView(
        systemImage: "person.2.slash",
        title: "No people to show",
        message: "Nothing matched this point in the chart."
      )
    }
  }

  private var rowList: some View {
    List {
      Section {
        ForEach(model.rows) { row in
          actorRow(row)
        }
        .listRowBackground(PHColor.surface)
      } footer: {
        footer
      }

      if model.hasMore, model.errorText == nil {
        loadMoreRow
      }
      if let errorText = model.errorText {
        inlineError(errorText)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .refreshable { await model.reload() }
  }

  private func actorRow(_ row: ActorRow) -> some View {
    Button {
      onOpenPerson(row.id)
      dismiss()
    } label: {
      HStack(spacing: PHSpacing.md) {
        VStack(alignment: .leading, spacing: 2) {
          Text(row.displayName)
            .font(.body.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          if let distinctID = row.distinctID {
            Text(distinctID)
              .font(PHFont.mono(12))
              .foregroundStyle(PHColor.textSecondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(PHColor.textTertiary)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// The sentinel: appearing at the end of the list fetches the next page.
  private var loadMoreRow: some View {
    HStack {
      Spacer()
      ProgressView()
      Spacer()
    }
    .frame(minHeight: 44)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
    .onAppear {
      Task { await model.loadMore() }
    }
  }

  private func inlineError(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      Text(text)
        .font(.footnote)
        .foregroundStyle(PHColor.danger)
      Button("Try again") {
        Task { await model.loadMore() }
      }
      .font(.footnote.weight(.semibold))
      .tint(PHColor.accent)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .listRowBackground(Color.clear)
    .listRowSeparator(.hidden)
  }

  @ViewBuilder private var footer: some View {
    if model.missingActorsCount > 0 {
      Text(
        model.missingActorsCount == 1
          ? "1 person is no longer available."
          : "\(model.missingActorsCount) people are no longer available."
      )
      .font(.caption)
      .foregroundStyle(PHColor.textTertiary)
    }
  }

  private var skeletonList: some View {
    List {
      ForEach(0..<8, id: \.self) { _ in
        SkeletonView(cornerRadius: 10)
          .frame(height: 40)
          .listRowBackground(Color.clear)
      }
    }
    .listStyle(.plain)
  }
}

/// Pages the actors query behind one point of an insight.
@MainActor
@Observable
final class ActorsSheetModel {
  /// Rows per request. A phone shows a handful at a time, so a small page keeps
  /// the first paint fast and the sentinel reachable.
  static let pageSize = 50

  private(set) var rows: [ActorRow] = []
  private(set) var isLoading = true
  private(set) var errorText: String?
  private(set) var hasMore = false
  private(set) var hogql: String?
  private(set) var missingActorsCount = 0
  var search = ""

  let source: DataQuery

  private let context: ProjectContext
  private let drill: ActorsDrill
  /// Bumped per first-page load so a slow response for an old search cannot
  /// overwrite fresh rows.
  private var generation = 0
  /// The search term the current rows answer. Nil until the first page lands.
  private var loadedSearch: String?
  private var isLoadingMore = false

  init(context: ProjectContext, source: DataQuery, drill: ActorsDrill) {
    self.context = context
    self.source = source
    self.drill = drill
  }

  /// Fetches the first page unless the rows on screen already answer this
  /// search. The appear task and the debounced search task both call this, so
  /// it must not fetch the same page twice.
  func loadFirstPage() async {
    guard loadedSearch != search else { return }
    await reload()
  }

  /// Fetches the first page again whatever the current rows hold.
  func reload() async {
    generation += 1
    let requested = generation
    let term = search
    loadedSearch = term
    isLoading = true
    errorText = nil
    do {
      let page = try await fetch(offset: 0, search: term)
      guard requested == generation else { return }
      rows = page.rows
      hasMore = page.hasMore
      missingActorsCount = page.missingActorsCount
      hogql = page.hogql ?? hogql
      isLoading = false
    } catch {
      guard requested == generation else { return }
      isLoading = false
      errorText = Self.failureText
    }
  }

  /// Appends the next page. Rows already on screen stay put.
  func loadMore() async {
    guard hasMore, !isLoading, !isLoadingMore else { return }
    isLoadingMore = true
    errorText = nil
    defer { isLoadingMore = false }

    let requested = generation
    do {
      let page = try await fetch(offset: rows.count, search: loadedSearch ?? search)
      guard requested == generation else { return }
      rows.append(contentsOf: page.rows)
      hasMore = page.hasMore
      missingActorsCount += page.missingActorsCount
      hogql = page.hogql ?? hogql
    } catch {
      guard requested == generation else { return }
      errorText = Self.failureText
    }
  }

  private static let failureText = "Couldn't load these people. Try again."

  private func fetch(offset: Int, search term: String) async throws -> ActorsPage {
    let query = ActorsQueryBuilder.make(
      source: source,
      drill: drill,
      limit: Self.pageSize,
      offset: offset,
      search: term.isEmpty ? nil : term
    )
    let result = try await context.runner.run(
      query,
      projectID: context.projectID,
      refresh: .blocking
    )
    guard case .unknown(let body) = result, let page = ActorsPage.parse(body) else {
      throw ActorsSheetError.unreadableResponse
    }
    return page
  }
}

enum ActorsSheetError: Error {
  case unreadableResponse
}
