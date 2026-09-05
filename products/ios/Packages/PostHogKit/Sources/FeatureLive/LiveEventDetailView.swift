import Foundation
import PostHogDesignSystem
import PostHogFoundation
import SwiftUI

/// Property sheet for one live event. Values render as text; nested arrays
/// and objects flatten to compact JSON strings.
public struct LiveEventDetailView: View {
  private let event: LiveEvent

  public init(event: LiveEvent) {
    self.event = event
  }

  public var body: some View {
    NavigationStack {
      List {
        Section {
          detailRow(key: "event", value: event.event)
          detailRow(key: "distinct_id", value: event.distinctID)
          if let timestamp = event.timestamp {
            detailRow(key: "timestamp", value: timestamp.formatted(date: .abbreviated, time: .standard))
          }
        }
        Section("Properties") {
          if sortedProperties.isEmpty {
            Text("This event has no properties.")
              .font(.subheadline)
              .foregroundStyle(PHColor.textSecondary)
          } else {
            ForEach(sortedProperties, id: \.key) { item in
              detailRow(key: item.key, value: displayString(item.value))
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(PHColor.background)
      .navigationTitle(event.event)
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var sortedProperties: [(key: String, value: JSONValue)] {
    if let object = event.properties.objectValue {
      return object.sorted { $0.key < $1.key }
    }
    if event.properties.isNull {
      return []
    }
    // A payload whose properties are not an object still shows as one row.
    return [(key: "properties", value: event.properties)]
  }

  private func detailRow(key: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(key)
        .font(PHFont.mono(12))
        .foregroundStyle(PHColor.textSecondary)
      Text(value)
        .font(.body)
        .foregroundStyle(PHColor.textPrimary)
        .textSelection(.enabled)
    }
    .padding(.vertical, 2)
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
