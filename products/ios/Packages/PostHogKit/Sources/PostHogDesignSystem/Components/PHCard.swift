import SwiftUI

/// The standard surface: white card on the warm background, hairline border,
/// soft shadow. Everything metric-shaped lives on one of these.
public struct PHCard<Content: View>: View {
  private let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    content
      .padding(PHSpacing.lg)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(PHColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous)
          .strokeBorder(PHColor.border, lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
  }
}

/// Small caps-style section label used above card content.
public struct PHCardLabel: View {
  private let text: String

  public init(_ text: String) {
    self.text = text
  }

  public var body: some View {
    Text(text)
      .font(.caption.weight(.bold))
      .kerning(0.2)
      .foregroundStyle(PHColor.textSecondary)
  }
}
