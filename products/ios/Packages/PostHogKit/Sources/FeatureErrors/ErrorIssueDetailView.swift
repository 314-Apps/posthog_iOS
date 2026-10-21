import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// One issue: header, triage actions, and the latest native stack trace.
/// Actions apply optimistically and revert if the PATCH fails.
public struct ErrorIssueDetailView: View {
  @State private var model: ErrorIssueDetailModel
  @State private var showAllFrames = false

  public init(context: ProjectContext, issueID: String) {
    self._model = State(initialValue: ErrorIssueDetailModel(context: context, issueID: issueID))
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        if let issue = model.issue {
          headerCard(issue)
          actionBar(issue)
          if let message = model.actionError {
            Text(message)
              .font(.footnote)
              .foregroundStyle(PHColor.danger)
          }
          stackTraceCard
        } else if model.loadFailed {
          EmptyStateView(
            systemImage: "wifi.exclamationmark",
            title: "Couldn't load this issue",
            message: "Check your connection and try again.",
            actionTitle: "Retry"
          ) {
            Task { await model.loadIssue() }
          }
        } else {
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 120)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 52)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 220)
        }
      }
      .padding(PHSpacing.lg)
    }
    .background(PHColor.background)
    .navigationTitle("Issue")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.loadIssue() }
    .task { await model.loadStackTrace() }
    .sensoryFeedback(.success, trigger: model.lastActionSucceeded)
  }

  private func headerCard(_ issue: ErrorTrackingIssue) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.sm) {
        HStack(alignment: .top, spacing: PHSpacing.sm) {
          Text(issue.name ?? "Untitled issue")
            .font(.headline)
            .foregroundStyle(PHColor.textPrimary)
            .textSelection(.enabled)
          Spacer()
          ErrorStatusBadge(status: issue.status)
        }
        if let description = issue.description, !description.isEmpty {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
            .textSelection(.enabled)
        }
        if let firstSeen = issue.firstSeen {
          Text("First seen \(RelativeDateFormat.ago(firstSeen))")
            .font(.caption)
            .foregroundStyle(PHColor.textTertiary)
        }
      }
    }
  }

  @ViewBuilder
  private func actionBar(_ issue: ErrorTrackingIssue) -> some View {
    switch issue.status {
    case .active:
      HStack(spacing: PHSpacing.sm) {
        actionButton("Resolve", prominent: true) {
          Task { await model.setStatus(.resolved) }
        }
        actionButton("Suppress", prominent: false) {
          Task { await model.setStatus(.suppressed) }
        }
      }
    case .resolved, .suppressed, .archived:
      actionButton("Reactivate", prominent: true) {
        Task { await model.setStatus(.active) }
      }
    case .unknown:
      EmptyView()
    }
  }

  private func actionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(prominent ? Color.white : PHColor.textPrimary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(prominent ? PHColor.accent : PHColor.surface, in: Capsule())
        .overlay(
          Capsule().strokeBorder(prominent ? PHColor.accent : PHColor.border, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
    .disabled(model.isUpdating)
    .opacity(model.isUpdating ? 0.6 : 1)
  }

  private var stackTraceCard: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Latest stack trace")
        switch model.stackTrace {
        case .loading:
          SkeletonView(cornerRadius: 10).frame(height: 140)
        case .unavailable:
          Text("Stack trace unavailable. Open the issue on the web for full details.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        case .loaded(let exceptions):
          ForEach(Array(exceptions.enumerated()), id: \.offset) { _, exception in
            exceptionSection(exception)
          }
          if hasHiddenFrames(exceptions) || showAllFrames {
            framesToggle
          }
        }
      }
    }
  }

  private var framesToggle: some View {
    Button {
      withAnimation { showAllFrames.toggle() }
    } label: {
      Text(showAllFrames ? "Show in-app frames" : "Show all frames")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(PHColor.link)
    }
    .buttonStyle(.plain)
  }

  private func exceptionSection(_ exception: ExceptionInfo) -> some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      VStack(alignment: .leading, spacing: 2) {
        Text(exception.type ?? "Exception")
          .font(PHFont.mono(15, weight: .bold))
          .foregroundStyle(PHColor.textPrimary)
          .textSelection(.enabled)
        if let value = exception.value, !value.isEmpty {
          Text(value)
            .font(.caption)
            .foregroundStyle(PHColor.textSecondary)
            .lineLimit(3)
            .textSelection(.enabled)
        }
      }
      ForEach(Array(visibleFrames(of: exception).enumerated()), id: \.offset) { _, frame in
        frameRow(frame)
      }
    }
  }

  private func visibleFrames(of exception: ExceptionInfo) -> [ExceptionInfo.Frame] {
    if showAllFrames { return exception.frames }
    let inApp = exception.frames.filter(\.inApp)
    return inApp.isEmpty ? exception.frames : inApp
  }

  private func hasHiddenFrames(_ exceptions: [ExceptionInfo]) -> Bool {
    exceptions.contains { exception in
      let inApp = exception.frames.filter(\.inApp)
      return !inApp.isEmpty && inApp.count < exception.frames.count
    }
  }

  private func frameRow(_ frame: ExceptionInfo.Frame) -> some View {
    HStack(alignment: .top, spacing: PHSpacing.sm) {
      Circle()
        .fill(frame.inApp ? PHColor.accent : Color.clear)
        .frame(width: 6, height: 6)
        .padding(.top, 5)
      VStack(alignment: .leading, spacing: 1) {
        Text(frame.displayName)
          .font(PHFont.mono(12))
          .foregroundStyle(PHColor.textPrimary)
          .lineLimit(1)
          .truncationMode(.middle)
        if let location = frame.location {
          Text(location)
            .font(.caption2)
            .foregroundStyle(PHColor.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .opacity(frame.inApp ? 1 : 0.45)
  }
}

@MainActor
@Observable
final class ErrorIssueDetailModel {
  enum StackTraceState: Equatable {
    case loading
    case loaded([ExceptionInfo])
    case unavailable
  }

  private(set) var issue: ErrorTrackingIssue?
  private(set) var loadFailed = false
  private(set) var stackTrace: StackTraceState = .loading
  private(set) var isUpdating = false
  private(set) var lastActionSucceeded = false
  private(set) var actionError: String?

  private let context: ProjectContext
  private let issueID: String

  init(context: ProjectContext, issueID: String) {
    self.context = context
    self.issueID = issueID
  }

  func loadIssue() async {
    loadFailed = false
    do {
      issue = try await context.client.errorTrackingIssue(projectID: context.projectID, issueID: issueID)
    } catch {
      PHLog.api.error("error issue load failed: \(error)")
      if issue == nil {
        loadFailed = true
      }
    }
  }

  func loadStackTrace() async {
    stackTrace = .loading
    // A quote in the id would break out of the SQL string literal.
    let escaped = issueID.replacingOccurrences(of: "'", with: "''")
    let sql = """
      SELECT properties FROM events \
      WHERE event = '$exception' AND JSONExtractString(properties, '$exception_issue_id') = '\(escaped)' \
      ORDER BY timestamp DESC LIMIT 1
      """
    do {
      let result = try await context.runner.run(.hogQL(HogQLQuery.make(sql)), projectID: context.projectID)
      stackTrace = parseStackTrace(result)
    } catch {
      PHLog.api.error("stack trace query failed: \(error)")
      stackTrace = .unavailable
    }
  }

  func setStatus(_ target: ErrorTrackingIssue.Status) async {
    guard let current = issue, !isUpdating, current.status != target else { return }
    isUpdating = true
    actionError = nil
    defer { isUpdating = false }
    // Optimistic: the badge flips now; a failed PATCH puts it back.
    issue = ErrorTrackingIssue(
      id: current.id,
      name: current.name,
      description: current.description,
      status: target,
      firstSeen: current.firstSeen,
      assignee: current.assignee
    )
    do {
      issue = try await context.client.updateErrorTrackingIssue(
        projectID: context.projectID,
        issueID: issueID,
        status: target
      )
      lastActionSucceeded.toggle()
      await context.cache.removeSubtree(context.cacheKey("errors-list"))
    } catch {
      PHLog.api.error("issue status update failed: \(error)")
      issue = current
      actionError = "Couldn't update the issue. Try again."
    }
  }

  private func parseStackTrace(_ result: QueryResult) -> StackTraceState {
    guard case .table(let table) = result, let cell = table.rows.first?.first else {
      return .unavailable
    }
    guard let json = propertiesJSON(from: cell) else { return .unavailable }
    let exceptions = ExceptionParser.parse(propertiesJSON: json)
    return exceptions.isEmpty ? .unavailable : .loaded(exceptions)
  }

  /// HogQL returns `properties` as a JSON string; tolerate an inlined object too.
  private func propertiesJSON(from cell: JSONValue) -> String? {
    if let string = cell.stringValue { return string }
    guard cell.objectValue != nil, let data = try? JSONEncoder().encode(cell) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
