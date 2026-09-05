import PostHogAPI
import PostHogDesignSystem
import SwiftUI

extension Survey.Lifecycle {
  var displayName: String {
    switch self {
    case .draft: "Draft"
    case .running: "Running"
    case .complete: "Complete"
    }
  }
}

extension Survey {
  /// "popover" reads as "Popover", "external_survey" as "External survey".
  var typeLabel: String? {
    guard let type, !type.isEmpty else { return nil }
    let words = type.replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
  }
}

/// Capsule badge in the flags style: green while collecting, muted otherwise.
struct SurveyLifecycleBadge: View {
  let lifecycle: Survey.Lifecycle

  var body: some View {
    Text(lifecycle.displayName)
      .font(.caption.weight(.bold))
      .foregroundStyle(foreground)
      .padding(.horizontal, PHSpacing.sm + 2)
      .padding(.vertical, 4)
      .background(fill, in: Capsule())
  }

  private var foreground: Color {
    switch lifecycle {
    case .draft: PHColor.textSecondary
    case .running: PHColor.success
    case .complete: PHColor.link
    }
  }

  private var fill: Color {
    switch lifecycle {
    case .draft: PHColor.divider
    case .running: PHColor.successFill.opacity(0.14)
    case .complete: PHColor.link.opacity(0.12)
    }
  }
}
