import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// One insight, full height, with local date/interval overrides that re-run
/// the query without ever writing back to the saved insight.
public struct InsightDetailView: View {
  @State private var model: InsightDetailModel

  public init(context: ProjectContext, insightID: Int) {
    self._model = State(initialValue: InsightDetailModel(context: context, insightID: insightID))
  }

  private let datePresets: [(String, String)] = [
    ("24h", "-24h"), ("7d", "-7d"), ("30d", "-30d"), ("90d", "-90d"),
  ]
  private let intervals: [(String, String)] = [
    ("Hour", "hour"), ("Day", "day"), ("Week", "week"), ("Month", "month"),
  ]

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: PHSpacing.sm) {
            ForEach(datePresets, id: \.1) { title, value in
              FilterChip(title, isSelected: model.dateFrom == value) {
                model.dateFrom = value
                Task { await model.run() }
              }
            }
            if model.isOverridden {
              FilterChip("Reset to saved", isSelected: false) {
                model.resetOverrides()
                Task { await model.run() }
              }
            }
          }
          .padding(.horizontal, PHSpacing.lg)
        }

        if model.supportsInterval {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PHSpacing.sm) {
              ForEach(intervals, id: \.1) { title, value in
                FilterChip(title, isSelected: model.interval == value) {
                  model.interval = value
                  Task { await model.run() }
                }
              }
            }
            .padding(.horizontal, PHSpacing.lg)
          }
        }

        PHCard {
          VStack(alignment: .leading, spacing: PHSpacing.md) {
            if let result = model.result, let query = model.query {
              InsightRenderer(query: query, result: result)
                .frame(minHeight: 240)
            } else {
              SkeletonView().frame(height: 240)
            }
          }
        }
        .padding(.horizontal, PHSpacing.lg)

        if let description = model.insight?.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
            .padding(.horizontal, PHSpacing.lg)
        }
      }
      .padding(.bottom, PHSpacing.xl)
    }
    .background(PHColor.background)
    .navigationTitle(model.insight?.displayName ?? " ")
    .navigationBarTitleDisplayMode(.large)
    .task { await model.load() }
  }
}

@MainActor
@Observable
final class InsightDetailModel {
  private(set) var insight: Insight?
  private(set) var query: DataQuery?
  private(set) var result: QueryResult?

  var dateFrom: String?
  var interval: String?

  private var savedQuery: DataQuery?
  private let context: ProjectContext
  private let insightID: Int

  init(context: ProjectContext, insightID: Int) {
    self.context = context
    self.insightID = insightID
  }

  var isOverridden: Bool { dateFrom != nil || interval != nil }

  var supportsInterval: Bool {
    guard let saved = savedQuery else { return false }
    return saved.renderSource.kind == "TrendsQuery"
  }

  func load() async {
    do {
      let loaded = try await context.client.insight(projectID: context.projectID, insightID: insightID)
      insight = loaded
      if let rawQuery = loaded.query {
        savedQuery = DataQuery(raw: rawQuery)
        // The saved cached result paints before the fresh run lands.
        if let cached = loaded.result, !cached.isNull, let saved = savedQuery {
          let body: JSONValue = cached.arrayValue != nil ? ["results": cached] : cached
          query = saved
          result = QueryResult.parse(kind: saved.renderSource.kind, body: body)
        }
        await run()
      }
    } catch {
      PHLog.api.error("insight load failed: \(error)")
    }
  }

  func resetOverrides() {
    dateFrom = nil
    interval = nil
  }

  func run() async {
    guard let saved = savedQuery else { return }
    let effective = applyingOverrides(to: saved)
    query = effective
    do {
      result = try await context.runner.run(effective, projectID: context.projectID, refresh: .blocking)
    } catch {
      PHLog.api.error("insight query failed: \(error)")
    }
  }

  private func applyingOverrides(to query: DataQuery) -> DataQuery {
    guard isOverridden else { return query }
    if case .insightViz(var node) = query, let source = node.source {
      node.source = applyingOverrides(to: source)
      return .insightViz(node)
    }
    guard var object = query.raw.objectValue else { return query }
    if let dateFrom {
      object["dateRange"] = ["date_from": .string(dateFrom)]
    }
    if let interval {
      object["interval"] = .string(interval)
    }
    return DataQuery(raw: .object(object))
  }
}
