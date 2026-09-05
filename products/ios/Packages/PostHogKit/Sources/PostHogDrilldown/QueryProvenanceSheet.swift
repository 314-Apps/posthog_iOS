import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI
import UIKit

/// Where a number came from: the query behind it, and the SQL that query
/// compiled to. Every field is optional, because a saved insight may carry any
/// shape the app does not model.
public struct QueryProvenanceSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var copyCount = 0

  private let provenance: QueryProvenance
  private let hogql: String?

  public init(query: DataQuery, hogql: String?) {
    self.provenance = QueryProvenance(query: query)
    self.hogql = hogql
  }

  public var body: some View {
    NavigationStack {
      List {
        querySection
        sqlSection
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(PHColor.background)
      .navigationTitle("Where this comes from")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .sensoryFeedback(.success, trigger: copyCount)
    }
  }

  private var querySection: some View {
    Section {
      detail("Insight", provenance.kindLabel)
      if let dateRange = provenance.dateRangeText {
        detail("Date range", dateRange)
      }
      if let interval = provenance.interval {
        detail("Interval", interval)
      }
      if !provenance.seriesNames.isEmpty {
        detail(
          provenance.seriesNames.count == 1 ? "Event" : "Events",
          provenance.seriesNames.joined(separator: ", ")
        )
      }
    } header: {
      PHCardLabel("Query")
    }
    .listRowBackground(PHColor.surface)
  }

  @ViewBuilder private var sqlSection: some View {
    Section {
      if let hogql, !hogql.isEmpty {
        ScrollView(.horizontal) {
          Text(hogql)
            .font(PHFont.mono(12, weight: .regular))
            .foregroundStyle(PHColor.textPrimary)
            .textSelection(.enabled)
            .padding(.vertical, PHSpacing.xs)
        }
        Button {
          UIPasteboard.general.string = hogql
          copyCount += 1
        } label: {
          Label("Copy SQL", systemImage: "doc.on.doc")
            .font(.subheadline.weight(.semibold))
        }
        .tint(PHColor.accent)
      } else {
        Text("The query plan is not available for this result.")
          .font(.footnote)
          .foregroundStyle(PHColor.textSecondary)
      }
    } header: {
      PHCardLabel("Generated SQL")
    }
    .listRowBackground(PHColor.surface)
  }

  private func detail(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: PHSpacing.md) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(PHColor.textSecondary)
      Spacer(minLength: PHSpacing.md)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PHColor.textPrimary)
        .multilineTextAlignment(.trailing)
        .textSelection(.enabled)
    }
  }
}

/// The facts a provenance sheet can state about a query, read straight from its
/// raw JSON. A field the payload does not carry, or carries in an unexpected
/// shape, stays nil rather than failing the read.
struct QueryProvenance: Sendable, Equatable {
  let kindLabel: String
  let dateFrom: String?
  let dateTo: String?
  let interval: String?
  let seriesNames: [String]

  init(query: DataQuery) {
    let source = query.renderSource
    let raw = source.raw
    self.kindLabel = Self.label(for: source.kind)
    self.dateFrom = raw["dateRange"]?["date_from"]?.stringValue
    self.dateTo = raw["dateRange"]?["date_to"]?.stringValue
    self.interval = raw["interval"]?.stringValue
    self.seriesNames = (raw["series"]?.arrayValue ?? []).compactMap(Self.seriesName(for:))
  }

  var dateRangeText: String? {
    switch (dateFrom, dateTo) {
    case (let from?, let to?): "\(from) to \(to)"
    case (let from?, nil): "\(from) to now"
    case (nil, let to?): "up to \(to)"
    default: nil
    }
  }

  private static func seriesName(for node: JSONValue) -> String? {
    if let custom = node["custom_name"]?.stringValue, !custom.isEmpty { return custom }
    if let name = node["name"]?.stringValue, !name.isEmpty { return name }
    if let event = node["event"]?.stringValue, !event.isEmpty { return event }
    // An events node with an explicit null event counts every event.
    if node["event"]?.isNull == true { return "All events" }
    return nil
  }

  private static let knownLabels = [
    "TrendsQuery": "Trends",
    "FunnelsQuery": "Funnel",
    "RetentionQuery": "Retention",
    "LifecycleQuery": "Lifecycle",
    "StickinessQuery": "Stickiness",
    "PathsQuery": "Paths",
    "HogQLQuery": "SQL",
    "EventsQuery": "Events",
    "WebOverviewQuery": "Web overview",
    "ActorsQuery": "People",
  ]

  /// Kinds outside the allowlist still reach a person, so turn the schema name
  /// into readable words instead of showing "ErrorTrackingQuery".
  private static func label(for kind: String) -> String {
    if let known = knownLabels[kind] { return known }
    guard !kind.isEmpty else { return "Unknown query" }

    var stem = kind
    for suffix in ["QueryNode", "Query", "Node"] where stem.hasSuffix(suffix) {
      stem = String(stem.dropLast(suffix.count))
      break
    }
    var words: [String] = []
    var current = ""
    for character in stem {
      if character.isUppercase, !current.isEmpty {
        words.append(current)
        current = ""
      }
      current.append(character)
    }
    if !current.isEmpty { words.append(current) }
    guard let first = words.first else { return "Unknown query" }
    return ([first] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
  }
}
