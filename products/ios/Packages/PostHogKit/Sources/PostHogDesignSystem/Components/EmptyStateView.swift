import SwiftUI

/// Empty and error states: one glyph, one wry line, one action. Never a dead end.
public struct EmptyStateView: View {
  private let systemImage: String
  private let title: String
  private let message: String
  private let actionTitle: String?
  private let action: (() -> Void)?

  public init(
    systemImage: String,
    title: String,
    message: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.systemImage = systemImage
    self.title = title
    self.message = message
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    VStack(spacing: PHSpacing.md) {
      Image(systemName: systemImage)
        .font(.system(size: 40, weight: .medium))
        .foregroundStyle(PHColor.textTertiary)
      VStack(spacing: PHSpacing.xs) {
        Text(title)
          .font(.headline)
          .foregroundStyle(PHColor.textPrimary)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(PHColor.textSecondary)
          .multilineTextAlignment(.center)
      }
      if let actionTitle, let action {
        Button(action: action) {
          Text(actionTitle)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, PHSpacing.xl)
            .frame(minHeight: 44)
            .background(PHColor.accent, in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(PHSpacing.xxl)
    .frame(maxWidth: .infinity)
  }
}
