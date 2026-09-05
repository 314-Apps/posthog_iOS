import PostHogAPI
import PostHogDesignSystem
import PostHogDrilldown
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// One dashboard: date-range chips, then every tile as an independent card.
/// Tiles paint from the serializer's cached result and refresh lazily.
public struct DashboardDetailView: View {
  @State private var model: DashboardDetailModel
  @State private var drilldown: DrilldownTarget?
  @State private var inspecting: QueryInspection?

  private let onOpenPerson: (String) -> Void

  public init(
    context: ProjectContext,
    dashboardID: Int,
    onOpenPerson: @escaping (String) -> Void = { _ in }
  ) {
    self._model = State(initialValue: DashboardDetailModel(context: context, dashboardID: dashboardID))
    self.onOpenPerson = onOpenPerson
  }

  private let presets: [(String, String?)] = [
    ("Today", "dStart"), ("7d", "-7d"), ("30d", "-30d"), ("90d", "-90d"), ("Default", nil),
  ]

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: PHSpacing.sm) {
            ForEach(presets, id: \.0) { title, dateFrom in
              FilterChip(title, isSelected: model.dateFromOverride == dateFrom) {
                model.dateFromOverride = dateFrom
                Task { await model.refreshTiles() }
              }
            }
          }
          .padding(.horizontal, PHSpacing.lg)
        }

        LazyVStack(spacing: PHSpacing.md) {
          ForEach(model.tiles) { tile in
            TileCardView(
              tile: tile,
              onDrill: { source, drill in
                drilldown = DrilldownTarget(source: source, drill: drill)
              },
              onInspect: { inspecting = QueryInspection(query: $0) }
            )
            .task { await model.refreshTileIfNeeded(tile.id) }
          }
        }
        .padding(.horizontal, PHSpacing.lg)
        .padding(.bottom, PHSpacing.xl)
      }
    }
    .background(PHColor.background)
    .navigationTitle(model.name)
    .navigationBarTitleDisplayMode(.large)
    .actorsDrilldown($drilldown, context: model.context, onOpenPerson: onOpenPerson)
    .queryProvenance($inspecting)
    .task { await model.load() }
    .refreshable { await model.load(forceRefresh: true) }
  }
}

/// One tile's render state.
struct TileState: Identifiable, Sendable {
  enum Content: Sendable {
    case loading
    case markdown(String)
    case insight(query: DataQuery, result: QueryResult)
    case failed
  }

  let id: Int
  let title: String?
  var content: Content
}

private struct TileCardView: View {
  let tile: TileState
  let onDrill: (DataQuery, ActorsDrill) -> Void
  let onInspect: (DataQuery) -> Void

  var body: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        if let title = tile.title {
          Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(PHColor.textPrimary)
        }
        switch tile.content {
        case .loading:
          SkeletonView().frame(height: 140)
        case .markdown(let body):
          Text(LocalizedStringKey(body))
            .font(.subheadline)
            .foregroundStyle(PHColor.textPrimary)
        case .insight(let query, let result):
          InsightRenderer(
            query: query,
            result: result,
            onDrill: { onDrill(query, $0) },
            onInspect: { onInspect(query) }
          )
        case .failed:
          UnsupportedInsightTile(kind: "unavailable")
        }
      }
    }
  }
}

@MainActor
@Observable
final class DashboardDetailModel {
  private(set) var name = " "
  private(set) var tiles: [TileState] = []
  var dateFromOverride: String??

  let context: ProjectContext
  private let dashboardID: Int
  private var queriesByTile: [Int: DataQuery] = [:]
  private var refreshedTiles: Set<Int> = []

  init(context: ProjectContext, dashboardID: Int) {
    self.context = context
    self.dashboardID = dashboardID
    self.dateFromOverride = .some(nil)
  }

  func load(forceRefresh: Bool = false) async {
    do {
      let detail = try await context.client.dashboard(projectID: context.projectID, dashboardID: dashboardID)
      name = detail.name
      if forceRefresh { refreshedTiles = [] }
      buildTiles(from: detail)
    } catch {
      PHLog.api.error("dashboard load failed: \(error)")
    }
  }

  private func buildTiles(from detail: DashboardDetail) {
    tiles = detail.tiles.compactMap { tile in
      if let text = tile.text?.body {
        return TileState(id: tile.id, title: nil, content: .markdown(text))
      }
      guard let insight = tile.insight, let rawQuery = insight.query else { return nil }
      let query = DataQuery(raw: rawQuery)
      queriesByTile[tile.id] = query
      // The serializer's cached result paints instantly; refresh comes after.
      if let cached = insight.result, !cached.isNull {
        let body: JSONValue = cached.arrayValue != nil ? ["results": cached] : cached
        let result = QueryResult.parse(kind: query.renderSource.kind, body: body)
        return TileState(id: tile.id, title: insight.displayName, content: .insight(query: query, result: result))
      }
      return TileState(id: tile.id, title: insight.displayName, content: .loading)
    }
  }

  /// Lazily refreshes a tile the first time it scrolls into view.
  func refreshTileIfNeeded(_ tileID: Int) async {
    guard !refreshedTiles.contains(tileID) else { return }
    refreshedTiles.insert(tileID)
    await run(tileID: tileID, refresh: .lazyAsync)
  }

  func refreshTiles() async {
    for tileID in queriesByTile.keys {
      await run(tileID: tileID, refresh: .blocking)
    }
  }

  private func run(tileID: Int, refresh: RefreshMode) async {
    guard var query = queriesByTile[tileID] else { return }
    if case .some(let dateFrom) = dateFromOverride, let dateFrom {
      query = applyDateOverride(query, dateFrom: dateFrom)
    }
    do {
      let result = try await context.runner.run(query, projectID: context.projectID, refresh: refresh)
      updateTile(tileID) { $0.content = .insight(query: query, result: result) }
    } catch {
      updateTile(tileID) { state in
        if case .loading = state.content {
          state.content = .failed
        }
      }
    }
  }

  private func applyDateOverride(_ query: DataQuery, dateFrom: String) -> DataQuery {
    if case .insightViz(var node) = query, let source = node.source {
      node.source = applyDateOverride(source, dateFrom: dateFrom)
      return .insightViz(node)
    }
    guard var object = query.raw.objectValue else { return query }
    object["dateRange"] = ["date_from": .string(dateFrom)]
    return DataQuery(raw: .object(object))
  }

  private func updateTile(_ tileID: Int, _ transform: (inout TileState) -> Void) {
    guard let index = tiles.firstIndex(where: { $0.id == tileID }) else { return }
    transform(&tiles[index])
  }
}
