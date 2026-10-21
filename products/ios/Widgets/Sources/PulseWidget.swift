import PostHogFoundation
import SwiftUI
import WidgetKit

/// The pulse snapshot the app writes to the App Group. Mirrors
/// AppShell.WidgetSnapshot; duplicated here so the widget links only
/// PostHogFoundation.
struct PulseSnapshot: Codable {
  let projectName: String
  let value: Double
  let deltaFraction: Double?
  let updatedAt: Date

  static func read() -> PulseSnapshot? {
    guard
      let url = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.com.posthog.ios")?
        .appendingPathComponent("pulse-snapshot.json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(PulseSnapshot.self, from: data)
  }
}

struct PulseEntry: TimelineEntry {
  let date: Date
  let snapshot: PulseSnapshot?
}

struct PulseProvider: TimelineProvider {
  func placeholder(in context: Context) -> PulseEntry {
    PulseEntry(
      date: .now,
      snapshot: PulseSnapshot(
        projectName: "Hogflix",
        value: 12847,
        deltaFraction: 0.124,
        updatedAt: .now
      )
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
    completion(PulseEntry(date: .now, snapshot: PulseSnapshot.read() ?? placeholder(in: context).snapshot))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
    let entry = PulseEntry(date: .now, snapshot: PulseSnapshot.read())
    // The app refreshes the snapshot on every Home load; ask WidgetKit to
    // re-read every 30 minutes so staleness captions stay honest.
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
  }
}

struct PulseWidgetView: View {
  var entry: PulseEntry

  private let accent = Color(red: 0.961, green: 0.306, blue: 0)
  private let good = Color(red: 0.118, green: 0.482, blue: 0.212)
  private let bad = Color(red: 0.702, green: 0.149, blue: 0.118)

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let snapshot = entry.snapshot {
        HStack(spacing: 4) {
          Circle().fill(accent).frame(width: 7, height: 7)
          Text(snapshot.projectName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Text(MetricFormat.compact(snapshot.value))
          .font(.system(size: 34, weight: .heavy, design: .rounded))
          .monospacedDigit()
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        HStack(spacing: 4) {
          Text("Users today")
            .font(.caption2)
            .foregroundStyle(.secondary)
          if let delta = snapshot.deltaFraction {
            Text(MetricFormat.signedPercent(fraction: delta))
              .font(.caption2.weight(.bold))
              .monospacedDigit()
              .foregroundStyle(delta >= 0 ? good : bad)
          }
        }
      } else {
        HStack(spacing: 4) {
          Circle().fill(accent).frame(width: 7, height: 7)
          Text("PostHog")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Text("Open the app to load your pulse")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .containerBackground(.background, for: .widget)
  }
}

struct PulseWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "PostHogPulse", provider: PulseProvider()) { entry in
      PulseWidgetView(entry: entry)
    }
    .configurationDisplayName("Project pulse")
    .description("Today's unique users at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct PostHogWidgetsBundle: WidgetBundle {
  var body: some Widget {
    PulseWidget()
  }
}
