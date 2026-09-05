import Foundation
import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// One person: identity header, their properties, and their latest events.
public struct PersonDetailView: View {
  private static let propertyRowCap = 40

  @State private var model: PersonDetailModel

  public init(context: ProjectContext, personID: String) {
    self._model = State(initialValue: PersonDetailModel(context: context, personID: personID))
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        if let person = model.person {
          header(person)
          propertiesCard(person)
          eventsCard
        } else if model.loadFailed {
          EmptyStateView(
            systemImage: "wifi.exclamationmark",
            title: "Couldn't load this person",
            message: "Check your connection and try again.",
            actionTitle: "Retry"
          ) {
            Task { await model.load() }
          }
        } else {
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 110)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 180)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 160)
        }
      }
      .padding(PHSpacing.lg)
    }
    .background(PHColor.background)
    .navigationTitle("Person")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
  }

  private func header(_ person: Person) -> some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      Text(person.displayName)
        .font(.title3.weight(.bold))
        .foregroundStyle(PHColor.textPrimary)
        .textSelection(.enabled)
      if let created = person.createdAt {
        Text("Created \(RelativeDateFormat.ago(created))")
          .font(.caption)
          .foregroundStyle(PHColor.textTertiary)
      }
      VStack(alignment: .leading, spacing: 2) {
        ForEach(person.distinctIDs, id: \.self) { distinctID in
          Text(distinctID)
            .font(PHFont.mono(12))
            .foregroundStyle(PHColor.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
      }
    }
  }

  private func propertiesCard(_ person: Person) -> some View {
    let rows = propertyRows(person)
    return PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Properties")
        if rows.isEmpty {
          Text("This person has no properties.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textTertiary)
        } else {
          ForEach(rows.prefix(Self.propertyRowCap), id: \.key) { row in
            VStack(alignment: .leading, spacing: 1) {
              Text(row.key)
                .font(PHFont.mono(12))
                .foregroundStyle(PHColor.textSecondary)
              Text(row.value)
                .font(.subheadline)
                .foregroundStyle(PHColor.textPrimary)
                .lineLimit(1)
                .textSelection(.enabled)
            }
          }
          if rows.count > Self.propertyRowCap {
            Text("and \(rows.count - Self.propertyRowCap) more")
              .font(.caption)
              .foregroundStyle(PHColor.textTertiary)
          }
        }
      }
    }
  }

  private var eventsCard: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Recent events")
        switch model.events {
        case .loading:
          SkeletonView(cornerRadius: 10).frame(height: 120)
        case .failed:
          Text("Couldn't load events. Open this person on the web for the full history.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        case .loaded(let rows) where rows.isEmpty:
          Text("No events yet.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textTertiary)
        case .loaded(let rows):
          ForEach(rows) { row in
            eventRow(row)
          }
        }
      }
    }
  }

  private func eventRow(_ row: PersonEventRow) -> some View {
    HStack(spacing: PHSpacing.md) {
      Text(row.event)
        .font(row.event.hasPrefix("$") ? PHFont.mono(13) : .subheadline)
        .foregroundStyle(PHColor.textPrimary)
        .lineLimit(1)
      Spacer()
      if let timestamp = row.timestamp {
        Text(RelativeDateFormat.ago(timestamp))
          .font(.caption)
          .foregroundStyle(PHColor.textTertiary)
      }
    }
  }

  private func propertyRows(_ person: Person) -> [(key: String, value: String)] {
    guard let object = person.propertiesRaw?.objectValue else { return [] }
    return object.sorted { $0.key < $1.key }.map { (key: $0.key, value: displayString($0.value)) }
  }

  private func displayString(_ value: JSONValue) -> String {
    switch value {
    case .string(let string): string
    case .bool(let bool): bool ? "true" : "false"
    case .null: "null"
    case .number, .array, .object: compactJSON(value)
    }
  }

  private func compactJSON(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard
      let data = try? encoder.encode(value),
      let text = String(bytes: data, encoding: .utf8)
    else { return "" }
    return text
  }
}

@MainActor
@Observable
final class PersonDetailModel {
  enum EventsState: Equatable {
    case loading
    case loaded([PersonEventRow])
    case failed
  }

  private(set) var person: Person?
  private(set) var loadFailed = false
  private(set) var events: EventsState = .loading

  private let context: ProjectContext
  private let personID: String

  init(context: ProjectContext, personID: String) {
    self.context = context
    self.personID = personID
  }

  func load() async {
    loadFailed = false
    do {
      person = try await context.client.person(projectID: context.projectID, personID: personID)
    } catch {
      PHLog.api.error("person load failed: \(error)")
      if person == nil {
        loadFailed = true
        return
      }
    }
    await loadEvents()
  }

  func loadEvents() async {
    events = .loading
    // The events table keys on the person UUID; the route id is the fallback.
    let personRef = person?.uuid ?? personID
    let query = DataQuery(raw: [
      "kind": "EventsQuery",
      "select": ["event", "timestamp"],
      "personId": .string(personRef),
      "orderBy": ["timestamp DESC"],
      "limit": 20,
    ])
    do {
      let result = try await context.runner.run(query, projectID: context.projectID)
      guard case .table(let table) = result else {
        events = .failed
        return
      }
      events = .loaded(PersonEventRow.rows(from: table))
    } catch {
      PHLog.api.error("person events query failed: \(error)")
      events = .failed
    }
  }
}

/// One row of the recent-events card, lifted out of the columnar result.
struct PersonEventRow: Equatable, Identifiable {
  let id: Int
  let event: String
  let timestamp: Date?

  static func rows(from table: TableResult) -> [PersonEventRow] {
    let eventIndex = table.columns.firstIndex(of: "event") ?? 0
    let timestampIndex = table.columns.firstIndex(of: "timestamp") ?? 1
    return table.rows.enumerated().compactMap { offset, row in
      guard let event = cell(row, at: eventIndex)?.stringValue else { return nil }
      return PersonEventRow(
        id: offset,
        event: event,
        timestamp: cell(row, at: timestampIndex)?.stringValue.flatMap(parseTimestamp)
      )
    }
  }

  private static func cell(_ row: [JSONValue], at index: Int) -> JSONValue? {
    row.indices.contains(index) ? row[index] : nil
  }

  private static func parseTimestamp(_ string: String) -> Date? {
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    if let date = try? Date(string, strategy: fractional) {
      return date
    }
    return try? Date(string, strategy: .iso8601)
  }
}
