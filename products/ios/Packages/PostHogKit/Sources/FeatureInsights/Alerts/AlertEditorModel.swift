import Foundation
import Observation
import PostHogAPI
import PostHogFoundation
import PostHogQueries

/// Form state, validation, and requests for creating or editing one alert.
@MainActor
@Observable
final class AlertEditorModel {
  static let intervals: [(label: String, value: String)] = [
    ("Hourly", "hourly"), ("Daily", "daily"), ("Weekly", "weekly"), ("Monthly", "monthly"),
  ]

  var name: String
  var enabled: Bool
  var interval: String
  var lowerText: String
  var upperText: String

  private(set) var isSaving = false
  private(set) var isDeleting = false
  private(set) var errorMessage: String?

  private let context: ProjectContext
  private let insightID: Int
  private let existing: InsightAlert?

  var isEditingExisting: Bool { existing != nil }
  var isBusy: Bool { isSaving || isDeleting }

  init(context: ProjectContext, insightID: Int, alert: InsightAlert? = nil) {
    self.context = context
    self.insightID = insightID
    self.existing = alert
    self.name = alert?.name ?? ""
    self.enabled = alert?.enabled ?? true
    self.interval = alert?.calculationInterval ?? "daily"
    self.lowerText = alert?.lowerThreshold.map(Self.boundText) ?? ""
    self.upperText = alert?.upperThreshold.map(Self.boundText) ?? ""
  }

  /// nil when the form can be submitted.
  var validationMessage: String? {
    guard let lower = Self.parseBound(lowerText), let upper = Self.parseBound(upperText) else {
      return "Bounds must be numbers. Enter a number or leave the field empty."
    }
    if let lower, let upper, lower > upper {
      return "The lower bound is above the upper bound. Adjust the values so lower stays below upper."
    }
    return nil
  }

  /// Returns true when the save landed, so the sheet can dismiss.
  func save() async -> Bool {
    guard !isBusy else { return false }
    if let message = validationMessage {
      errorMessage = message
      return false
    }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil
    let body = InsightAlert.payload(
      name: name.trimmingCharacters(in: .whitespaces),
      enabled: enabled,
      insightID: insightID,
      calculationInterval: interval,
      lower: Self.parseBound(lowerText).flatMap { $0 },
      upper: Self.parseBound(upperText).flatMap { $0 }
    )
    do {
      if let existing {
        _ = try await context.client.updateInsightAlert(
          projectID: context.projectID,
          alertID: existing.id,
          body: body
        )
      } else {
        _ = try await context.client.createInsightAlert(projectID: context.projectID, body: body)
      }
      return true
    } catch {
      PHLog.api.error("alert save failed: \(error)")
      errorMessage = "Couldn't save the alert. Check the values and try again."
      return false
    }
  }

  /// Returns true when the delete landed, so the sheet can dismiss.
  func delete() async -> Bool {
    guard let existing, !isBusy else { return false }
    isDeleting = true
    defer { isDeleting = false }
    errorMessage = nil
    do {
      try await context.client.deleteInsightAlert(projectID: context.projectID, alertID: existing.id)
      return true
    } catch {
      PHLog.api.error("alert delete failed: \(error)")
      errorMessage = "Couldn't delete the alert. Check your connection and try again."
      return false
    }
  }

  /// Outer nil means the text is not a number; inner nil means the field is empty.
  private static func parseBound(_ text: String) -> Double?? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return .some(nil) }
    guard let value = Double(trimmed) else { return nil }
    return value
  }

  private static func boundText(_ value: Double) -> String {
    let isWhole = value.truncatingRemainder(dividingBy: 1) == 0
    if isWhole, value >= Double(Int64.min), value <= Double(Int64.max) {
      return String(Int64(value))
    }
    return String(value)
  }
}
