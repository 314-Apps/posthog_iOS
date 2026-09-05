import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import PostHogQueries
import SwiftUI

/// Flag control: the master toggle behind a confirmation sheet, rollout and
/// conditions rendered read-only, and the activity feed that makes mobile
/// toggling trustworthy.
public struct FlagDetailView: View {
  @State private var model: FlagDetailModel
  @State private var confirmingChange = false

  public init(context: ProjectContext, flagID: Int) {
    self._model = State(initialValue: FlagDetailModel(context: context, flagID: flagID))
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        if let flag = model.flag {
          header(flag)
          toggleCard(flag)
          conditionsCard(flag)
          activityCard
        } else {
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 90)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 70)
          SkeletonView(cornerRadius: PHRadius.card).frame(height: 160)
        }
      }
      .padding(PHSpacing.lg)
    }
    .background(PHColor.background)
    .navigationTitle("Feature flag")
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.load() }
    .confirmationDialog(
      model.flag?.active == true ? "Turn off this flag?" : "Turn on this flag?",
      isPresented: $confirmingChange,
      titleVisibility: .visible
    ) {
      Button(
        model.flag?.active == true ? "Turn off flag" : "Turn on flag",
        role: model.flag?.active == true ? .destructive : nil
      ) {
        Task { await model.toggle() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        model.flag?.active == true
          ? "Users currently matching will stop receiving it on their next evaluation."
          : "Matching users start receiving it on their next evaluation.")
    }
    .sensoryFeedback(.success, trigger: model.lastToggleSucceeded)
  }

  private func header(_ flag: FeatureFlag) -> some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      HStack(spacing: PHSpacing.sm) {
        Text(flag.key)
          .font(PHFont.mono(18, weight: .bold))
          .foregroundStyle(PHColor.textPrimary)
          .textSelection(.enabled)
        Spacer()
      }
      if !flag.name.isEmpty {
        Text(flag.name)
          .font(.subheadline)
          .foregroundStyle(PHColor.textSecondary)
      }
      HStack(spacing: PHSpacing.sm) {
        Text(flag.active ? "Enabled" : "Disabled")
          .font(.caption.weight(.bold))
          .foregroundStyle(flag.active ? PHColor.success : PHColor.textSecondary)
          .padding(.horizontal, PHSpacing.sm + 2)
          .padding(.vertical, 4)
          .background(
            (flag.active ? PHColor.successFill.opacity(0.14) : PHColor.divider),
            in: Capsule()
          )
        Text(flag.rolloutSummary)
          .font(.caption.weight(.semibold))
          .foregroundStyle(PHColor.textSecondary)
      }
    }
  }

  private func toggleCard(_ flag: FeatureFlag) -> some View {
    PHCard {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(flag.active ? "Flag is on" : "Flag is off")
            .font(.headline)
            .foregroundStyle(PHColor.textPrimary)
          Text(model.isToggling ? "Saving…" : "Serving \(flag.rolloutSummary.lowercased())")
            .font(.caption)
            .foregroundStyle(PHColor.textTertiary)
        }
        Spacer()
        Toggle(
          "",
          isOn: Binding(
            get: { flag.active },
            set: { _ in confirmingChange = true }
          )
        )
        .labelsHidden()
        .tint(PHColor.accent)
        .disabled(model.isToggling)
      }
    }
  }

  private func conditionsCard(_ flag: FeatureFlag) -> some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Release conditions")
        if flag.conditionGroups.isEmpty {
          Text("Served to everyone when enabled.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textSecondary)
        } else {
          ForEach(Array(flag.conditionGroups.enumerated()), id: \.offset) { index, group in
            conditionGroup(index: index, group: group)
          }
        }
        Text("Edit conditions on the web")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(PHColor.link)
      }
    }
  }

  private func conditionGroup(index: Int, group: JSONValue) -> some View {
    let rollout = group["rollout_percentage"]?.numberValue ?? 100
    let propertyCount = group["properties"]?.arrayValue?.count ?? 0
    return VStack(alignment: .leading, spacing: 4) {
      Text("Set \(index + 1) · \(Int(rollout))% of matching users")
        .font(.caption.weight(.bold))
        .foregroundStyle(PHColor.textSecondary)
      Text(propertyCount == 0 ? "No property filters" : "\(propertyCount) property filter(s)")
        .font(.caption)
        .foregroundStyle(PHColor.textTertiary)
    }
    .padding(PHSpacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(PHColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var activityCard: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Recent activity")
        if model.activity.isEmpty {
          Text("No changes recorded yet.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textTertiary)
        } else {
          ForEach(model.activity.prefix(10)) { entry in
            HStack(alignment: .top, spacing: PHSpacing.md) {
              Circle()
                .fill(PHColor.series(at: 0).opacity(0.8))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
              VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.actorName) \(describe(entry))")
                  .font(.subheadline)
                  .foregroundStyle(PHColor.textPrimary)
                Text(RelativeDateFormat.ago(entry.createdAt))
                  .font(.caption)
                  .foregroundStyle(PHColor.textTertiary)
              }
            }
          }
        }
      }
    }
  }

  private func describe(_ entry: ActivityLogEntry) -> String {
    switch entry.activity {
    case "updated": "updated the flag"
    case "created": "created the flag"
    case "deleted": "deleted the flag"
    default: entry.activity.replacingOccurrences(of: "_", with: " ")
    }
  }
}

@MainActor
@Observable
final class FlagDetailModel {
  private(set) var flag: FeatureFlag?
  private(set) var activity: [ActivityLogEntry] = []
  private(set) var isToggling = false
  private(set) var lastToggleSucceeded = false

  private let context: ProjectContext
  private let flagID: Int

  init(context: ProjectContext, flagID: Int) {
    self.context = context
    self.flagID = flagID
  }

  func load() async {
    do {
      flag = try await context.client.featureFlag(projectID: context.projectID, flagID: flagID)
    } catch {
      PHLog.api.error("flag load failed: \(error)")
    }
    activity =
      (try? await context.client.featureFlagActivity(projectID: context.projectID, flagID: flagID))?
      .results ?? []
  }

  func toggle() async {
    guard let current = flag, !isToggling else { return }
    isToggling = true
    defer { isToggling = false }
    do {
      flag = try await context.client.setFeatureFlag(
        projectID: context.projectID,
        flagID: flagID,
        enabled: !current.active
      )
      lastToggleSucceeded.toggle()
      await context.cache.removeSubtree("\(context.region.storageKey)/\(context.projectID)/flags-list")
      activity =
        (try? await context.client.featureFlagActivity(projectID: context.projectID, flagID: flagID))?
        .results ?? []
    } catch {
      PHLog.api.error("flag toggle failed: \(error)")
    }
  }
}
