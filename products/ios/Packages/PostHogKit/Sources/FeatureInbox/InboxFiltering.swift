import Foundation
import PostHogAPI

/// Chip row filter. Raw values are the visible chip titles.
enum InboxFilter: String, CaseIterable {
  case all = "All"
  case alerts = "Alerts"
  case mentions = "Mentions"
  case errors = "Errors"

  func matches(_ type: NotificationEvent.EventType) -> Bool {
    switch self {
    case .all: true
    case .alerts: type == .alertFiring
    case .mentions: type == .commentMention
    case .errors: type == .issueAssigned || type == .pipelineFailure
    }
  }
}

/// List section buckets. Raw values are the visible section headers.
enum InboxSection: String {
  case today = "Today"
  case thisWeek = "This week"
  case earlier = "Earlier"
}

struct InboxSectionGroup: Identifiable, Equatable {
  let section: InboxSection
  let events: [NotificationEvent]
  var id: InboxSection { section }
}

enum InboxGrouping {
  /// Buckets events into Today / This week / Earlier, newest first.
  /// `now` is injectable so tests do not depend on the wall clock.
  static func grouped(
    _ events: [NotificationEvent],
    now: Date = .now,
    calendar: Calendar = .current
  ) -> [InboxSectionGroup] {
    let weekFloor = calendar.date(byAdding: .day, value: -7, to: now) ?? now
    var buckets: [InboxSection: [NotificationEvent]] = [:]
    for event in events.sorted(by: { $0.createdAt > $1.createdAt }) {
      let section: InboxSection =
        if calendar.isDate(event.createdAt, inSameDayAs: now) {
          .today
        } else if event.createdAt >= weekFloor {
          .thisWeek
        } else {
          .earlier
        }
      buckets[section, default: []].append(event)
    }
    return [InboxSection.today, .thisWeek, .earlier].compactMap { section in
      guard let events = buckets[section], !events.isEmpty else { return nil }
      return InboxSectionGroup(section: section, events: events)
    }
  }
}
