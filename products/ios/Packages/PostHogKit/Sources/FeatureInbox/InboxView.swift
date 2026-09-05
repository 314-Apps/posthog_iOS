import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Inbox root: alerts, mentions, and assignments in one list. Reads mutate
/// optimistically because a swipe must feel instant on a slow connection;
/// the model reverts if the API rejects the change.
public struct InboxView: View {
  @State private var model: InboxModel

  private let onOpen: (InboxDestination) -> Void

  public init(context: ProjectContext, onOpen: @escaping (InboxDestination) -> Void) {
    self._model = State(initialValue: InboxModel(context: context))
    self.onOpen = onOpen
  }

  public var body: some View {
    VStack(spacing: 0) {
      filterChips
      content
    }
    .background(PHColor.background)
    .navigationTitle("Inbox")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Mark all read") {
          Task { await model.markAllRead() }
        }
        .font(.subheadline.weight(.semibold))
        .tint(PHColor.link)
        .disabled(model.isMarkingAllRead)
      }
    }
    .task { await model.load() }
  }

  @ViewBuilder private var content: some View {
    switch model.state {
    case .loading:
      List {
        ForEach(0..<8, id: \.self) { _ in
          SkeletonView(cornerRadius: 10).frame(height: 56).listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
    case .failed(let message):
      EmptyStateView(
        systemImage: "wifi.exclamationmark",
        title: "Couldn't load notifications",
        message: message,
        actionTitle: "Retry"
      ) {
        Task { await model.load(forceRefresh: true) }
      }
      .frame(maxHeight: .infinity)
    case .loaded where model.sections.isEmpty:
      EmptyStateView(
        systemImage: "bell",
        title: "No notifications",
        message: "Alerts, mentions, and assignments show up here."
      )
      .frame(maxHeight: .infinity)
    case .loaded:
      List {
        ForEach(model.sections) { group in
          Section(group.section.rawValue) {
            ForEach(group.events) { event in
              row(event)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .refreshable { await model.load(forceRefresh: true) }
    }
  }

  private var filterChips: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: PHSpacing.sm) {
        ForEach(InboxFilter.allCases, id: \.self) { filter in
          FilterChip(filter.rawValue, isSelected: model.filter == filter) {
            model.filter = filter
          }
        }
      }
      .padding(.horizontal, PHSpacing.lg)
    }
    .padding(.vertical, PHSpacing.sm)
  }

  private func row(_ event: NotificationEvent) -> some View {
    Button {
      onOpen(.forEvent(event))
    } label: {
      HStack(alignment: .top, spacing: PHSpacing.md) {
        iconSquare(event.type)
        VStack(alignment: .leading, spacing: 2) {
          Text(event.title)
            .font(.subheadline.weight(event.isRead ? .regular : .bold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(2)
          if let body = event.body, !body.isEmpty {
            Text(body)
              .font(.caption)
              .foregroundStyle(PHColor.textSecondary)
              .lineLimit(2)
          }
          Text(RelativeDateFormat.ago(event.createdAt))
            .font(.caption2)
            .foregroundStyle(PHColor.textTertiary)
        }
        Spacer(minLength: 0)
        if !event.isRead {
          Circle()
            .fill(PHColor.accent)
            .frame(width: 8, height: 8)
            .padding(.top, 6)
        }
      }
      .frame(minHeight: 44)
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(event.isRead ? "Mark unread" : "Mark read") {
        Task { await model.setRead(!event.isRead, id: event.id) }
      }
      .tint(PHColor.link)
    }
  }

  private func iconSquare(_ type: NotificationEvent.EventType) -> some View {
    Image(systemName: type.iconName)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(type.tint)
      .frame(width: 34, height: 34)
      .background(type.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
  }
}

extension NotificationEvent.EventType {
  var iconName: String {
    switch self {
    case .alertFiring: "exclamationmark.triangle"
    case .commentMention: "bubble.left"
    case .issueAssigned: "ladybug"
    case .approvalResolved: "checkmark"
    case .approvalRequested: "person.crop.circle.badge.questionmark"
    case .pipelineFailure: "exclamationmark.arrow.triangle.2.circlepath"
    case .unknown: "bell"
    }
  }

  var tint: Color {
    switch self {
    case .alertFiring: PHColor.accent
    case .commentMention: PHColor.link
    case .issueAssigned: PHColor.danger
    case .approvalResolved: PHColor.success
    case .approvalRequested: PHColor.textSecondary
    case .pipelineFailure: PHColor.highlight
    case .unknown: PHColor.textSecondary
    }
  }
}

@MainActor
@Observable
final class InboxModel {
  enum State {
    case loading
    case loaded
    case failed(String)
  }

  private(set) var state: State = .loading
  private(set) var events: [NotificationEvent] = []
  private(set) var isMarkingAllRead = false
  var filter: InboxFilter = .all

  private let context: ProjectContext

  init(context: ProjectContext) {
    self.context = context
  }

  var sections: [InboxSectionGroup] {
    InboxGrouping.grouped(events.filter { filter.matches($0.type) })
  }

  func load(forceRefresh: Bool = false) async {
    let key = context.cacheKey("inbox")
    if !forceRefresh, events.isEmpty {
      if let hit = await context.cache.read(key, as: [NotificationEvent].self, staleAfter: 60) {
        events = hit.value
        state = .loaded
        if !hit.isStale { return }
      }
    }
    do {
      let page = try await context.client.notifications(projectID: context.projectID)
      events = page.results
      state = .loaded
      await context.cache.write(key, value: events)
    } catch {
      if events.isEmpty {
        state = .failed("Check your connection and try again.")
      }
    }
  }

  func setRead(_ isRead: Bool, id: String) async {
    guard let index = events.firstIndex(where: { $0.id == id }), events[index].isRead != isRead else {
      return
    }
    let previous = events
    events[index].isRead = isRead
    do {
      if isRead {
        try await context.client.markNotificationRead(projectID: context.projectID, notificationID: id)
      } else {
        try await context.client.markNotificationUnread(projectID: context.projectID, notificationID: id)
      }
      await context.cache.write(context.cacheKey("inbox"), value: events)
    } catch {
      events = previous
    }
  }

  func markAllRead() async {
    guard !isMarkingAllRead, events.contains(where: { !$0.isRead }) else { return }
    isMarkingAllRead = true
    defer { isMarkingAllRead = false }
    let previous = events
    events = events.map { event in
      var updated = event
      updated.isRead = true
      return updated
    }
    do {
      try await context.client.markAllNotificationsRead(projectID: context.projectID)
      await context.cache.write(context.cacheKey("inbox"), value: events)
    } catch {
      events = previous
    }
  }
}
