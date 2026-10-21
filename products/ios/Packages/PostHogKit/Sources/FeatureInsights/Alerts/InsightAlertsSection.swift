import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// The alerts card for one insight: each alert as a tappable row with a state
/// badge, plus a row to create a new one. Embeds in the insight detail screen.
public struct InsightAlertsSection: View {
  @State private var model: InsightAlertsModel
  @State private var editorRoute: AlertEditorRoute?

  public init(context: ProjectContext, insightID: Int) {
    self._model = State(initialValue: InsightAlertsModel(context: context, insightID: insightID))
  }

  public var body: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Alerts")
        switch model.state {
        case .loading:
          SkeletonView().frame(height: 44)
        case .failed:
          failedContent
        case .loaded:
          if model.alerts.isEmpty {
            Text("No alerts yet. Add one to get notified when this insight crosses a threshold.")
              .font(.subheadline)
              .foregroundStyle(PHColor.textSecondary)
          } else {
            ForEach(model.alerts) { alert in
              alertRow(alert)
            }
          }
          newAlertRow
        }
      }
    }
    .sheet(item: $editorRoute) { route in
      AlertEditorSheet(
        model: AlertEditorModel(context: model.context, insightID: model.insightID, alert: route.alert)
      ) {
        model.noteChangeSucceeded()
        Task { await model.load() }
      }
    }
    .sensoryFeedback(.success, trigger: model.changeCount)
    .task { await model.load() }
  }

  private var failedContent: some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      Text("Couldn't load alerts.")
        .font(.subheadline)
        .foregroundStyle(PHColor.textSecondary)
      Button {
        Task { await model.load() }
      } label: {
        Text("Try again")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(PHColor.link)
          .frame(minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private func alertRow(_ alert: InsightAlert) -> some View {
    Button {
      editorRoute = AlertEditorRoute(alert: alert)
    } label: {
      HStack(spacing: PHSpacing.md) {
        VStack(alignment: .leading, spacing: 1) {
          Text(alert.name.isEmpty ? "Untitled alert" : alert.name)
            .font(.body.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          if let caption = intervalCaption(alert.calculationInterval) {
            Text(caption)
              .font(.caption)
              .foregroundStyle(PHColor.textTertiary)
          }
        }
        Spacer()
        stateBadge(alert)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var newAlertRow: some View {
    Button {
      editorRoute = AlertEditorRoute(alert: nil)
    } label: {
      HStack(spacing: PHSpacing.sm) {
        Image(systemName: "plus.circle.fill")
          .font(.subheadline)
        Text("New alert")
          .font(.body.weight(.semibold))
      }
      .foregroundStyle(PHColor.accent)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private struct BadgeStyle {
    let title: String
    let foreground: Color
    let fill: Color
  }

  private func stateBadge(_ alert: InsightAlert) -> some View {
    let style = badgeStyle(alert)
    return Text(style.title)
      .font(.caption.weight(.bold))
      .foregroundStyle(style.foreground)
      .padding(.horizontal, PHSpacing.sm + 2)
      .padding(.vertical, 4)
      .background(style.fill, in: Capsule())
  }

  private func badgeStyle(_ alert: InsightAlert) -> BadgeStyle {
    guard alert.enabled else {
      return BadgeStyle(title: "Paused", foreground: PHColor.textSecondary, fill: PHColor.divider)
    }
    if alert.state?.uppercased() == "FIRING" {
      return BadgeStyle(title: "Firing", foreground: PHColor.danger, fill: PHColor.dangerFill.opacity(0.14))
    }
    return BadgeStyle(title: "OK", foreground: PHColor.success, fill: PHColor.successFill.opacity(0.14))
  }

  private func intervalCaption(_ interval: String?) -> String? {
    guard let interval, !interval.isEmpty else { return nil }
    return "Checks \(interval.replacingOccurrences(of: "_", with: " "))"
  }
}

private struct AlertEditorRoute: Identifiable {
  let alert: InsightAlert?
  var id: String { alert?.id ?? "new" }
}

@MainActor
@Observable
final class InsightAlertsModel {
  enum State {
    case loading
    case loaded
    case failed
  }

  private(set) var state: State = .loading
  private(set) var alerts: [InsightAlert] = []
  private(set) var changeCount = 0

  let context: ProjectContext
  let insightID: Int

  init(context: ProjectContext, insightID: Int) {
    self.context = context
    self.insightID = insightID
  }

  func load() async {
    do {
      let page = try await context.client.insightAlerts(projectID: context.projectID, insightID: insightID)
      // Older servers ignore the insight_id param, so filter here too.
      alerts = page.results.filter { $0.insightID == insightID }
      state = .loaded
    } catch {
      PHLog.api.error("alerts load failed: \(error)")
      state = alerts.isEmpty ? .failed : .loaded
    }
  }

  func noteChangeSucceeded() {
    changeCount += 1
  }
}
