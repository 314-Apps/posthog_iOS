import PostHogAPI
import PostHogDesignSystem
import PostHogFoundation
import SwiftUI

struct SurveyDatePresetRow: View {
  @Binding var preset: SurveyDatePreset

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: PHSpacing.sm) {
        ForEach(SurveyDatePreset.allCases) { option in
          Button {
            preset = option
          } label: {
            Text(option.label)
              .font(.caption.weight(.semibold))
              .foregroundStyle(preset == option ? Color.white : PHColor.textPrimary)
              .padding(.horizontal, PHSpacing.md)
              .padding(.vertical, 8)
              .background(
                preset == option ? PHColor.accent : PHColor.surfaceSecondary,
                in: Capsule()
              )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct SurveyTabRow: View {
  enum Tab: String, CaseIterable, Identifiable {
    case results
    case responses
    var id: String { rawValue }
    var label: String {
      switch self {
      case .results: "Results"
      case .responses: "Responses"
      }
    }
  }

  @Binding var tab: Tab

  var body: some View {
    Picker("Section", selection: $tab) {
      ForEach(Tab.allCases) { option in
        Text(option.label).tag(option)
      }
    }
    .pickerStyle(.segmented)
  }
}

struct SurveyFunnelCard: View {
  let funnel: SurveyFunnel

  var body: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        PHCardLabel("Funnel")
        HStack(alignment: .top, spacing: PHSpacing.xl) {
          StatTile(label: "Shown", value: MetricFormat.compact(funnel.shown))
          StatTile(label: "Responded", value: MetricFormat.compact(funnel.sent))
          StatTile(label: "Dismissed", value: MetricFormat.compact(funnel.dismissed))
        }
        HStack(spacing: PHSpacing.lg) {
          rateLabel("Response rate", funnel.responseRate)
          rateLabel("Dismissal rate", funnel.dismissalRate)
        }
      }
    }
  }

  private func rateLabel(_ title: String, _ rate: Double) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption)
        .foregroundStyle(PHColor.textTertiary)
      Text(MetricFormat.percent(fraction: rate / 100))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PHColor.textPrimary)
    }
  }
}

struct SurveyQuestionResultCard: View {
  let result: SurveyQuestionResult

  var body: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.md) {
        HStack(alignment: .firstTextBaseline) {
          Text(typeLabel)
            .font(.caption.weight(.bold))
            .foregroundStyle(PHColor.textSecondary)
          Spacer()
          Text("\(result.total) responses")
            .font(.caption)
            .foregroundStyle(PHColor.textTertiary)
        }
        Text(result.question.text.isEmpty ? "Question \(result.question.index + 1)" : result.question.text)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(PHColor.textPrimary)

        switch result {
        case .rating(_, _, let bars, let average, let nps):
          RatingColumns(bars: bars)
          if let average {
            Text("Average \(String(format: "%.1f", average))")
              .font(.caption)
              .foregroundStyle(PHColor.textSecondary)
          }
          if let nps {
            NpsSummary(nps: nps, total: result.total)
          }
        case .choice(_, _, let bars, let sampled):
          ForEach(bars) { bar in
            HorizontalResultBar(bar: bar)
          }
          if sampled {
            sampledNote
          }
        case .open(_, _, let answers, let sampled):
          if answers.isEmpty {
            Text("No open-text answers in this range.")
              .font(.subheadline)
              .foregroundStyle(PHColor.textTertiary)
          } else {
            ForEach(answers.prefix(20)) { answer in
              VStack(alignment: .leading, spacing: 4) {
                Text(answer.text)
                  .font(.subheadline)
                  .foregroundStyle(PHColor.textPrimary)
                Text(answer.distinctID)
                  .font(.caption2)
                  .foregroundStyle(PHColor.textTertiary)
              }
              .padding(.vertical, 4)
            }
          }
          if sampled {
            sampledNote
          }
        case .link:
          Text("Link questions do not collect answers.")
            .font(.subheadline)
            .foregroundStyle(PHColor.textTertiary)
        }
      }
    }
  }

  private var typeLabel: String {
    switch result.question.type {
    case .open: "Open text"
    case .link: "Link"
    case .rating: "Rating"
    case .singleChoice: "Single choice"
    case .multipleChoice: "Multiple choice"
    }
  }

  private var sampledNote: some View {
    Text("Based on the loaded responses, not the full range.")
      .font(.caption)
      .foregroundStyle(PHColor.textTertiary)
  }
}

struct SurveyResponseRowCard: View {
  let row: PostHogAPI.SurveyResponseRow

  var body: some View {
    PHCard {
      VStack(alignment: .leading, spacing: PHSpacing.sm) {
        HStack {
          Text(row.distinctID)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PHColor.textPrimary)
            .lineLimit(1)
          Spacer()
          Text(row.submittedAt)
            .font(.caption2)
            .foregroundStyle(PHColor.textTertiary)
            .lineLimit(1)
        }
        ForEach(Array(row.answers.enumerated()), id: \.offset) { _, answer in
          let text = answerText(answer.answer)
          if !text.isEmpty {
            Text(text)
              .font(.subheadline)
              .foregroundStyle(PHColor.textSecondary)
          }
        }
      }
    }
  }

  private func answerText(_ value: PostHogFoundation.JSONValue?) -> String {
    guard let value else { return "" }
    if let string = value.stringValue { return string }
    if let array = value.arrayValue {
      return array.compactMap(\.stringValue).joined(separator: ", ")
    }
    if let number = value.numberValue { return String(Int(number)) }
    return ""
  }
}

private struct HorizontalResultBar: View {
  let bar: ResultBar

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(bar.label)
          .font(.subheadline)
          .foregroundStyle(PHColor.textPrimary)
          .lineLimit(2)
        Spacer()
        Text("\(bar.count) · \(Int(round(bar.share * 100)))%")
          .font(.caption)
          .foregroundStyle(PHColor.textTertiary)
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(PHColor.surfaceSecondary)
          Capsule()
            .fill(PHColor.accent)
            .frame(width: max(geo.size.width * bar.share, bar.count > 0 ? 4 : 0))
        }
      }
      .frame(height: 8)
    }
  }
}

private struct RatingColumns: View {
  let bars: [ResultBar]

  var body: some View {
    let maxCount = max(bars.map(\.count).max() ?? 1, 1)
    HStack(alignment: .bottom, spacing: 4) {
      ForEach(bars) { bar in
        VStack(spacing: 4) {
          Text(bar.count > 0 ? "\(Int(round(bar.share * 100)))%" : "")
            .font(.system(size: 9))
            .foregroundStyle(PHColor.textTertiary)
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(PHColor.accent)
            .frame(height: max(CGFloat(bar.count) / CGFloat(maxCount) * 80, bar.count > 0 ? 2 : 0))
          Text(bar.label)
            .font(.caption2)
            .foregroundStyle(PHColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
      }
    }
    .frame(height: 120)
  }
}

private struct NpsSummary: View {
  let nps: NpsBreakdown
  let total: Int

  var body: some View {
    VStack(alignment: .leading, spacing: PHSpacing.sm) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("\(nps.score)")
          .font(.title2.weight(.bold))
          .foregroundStyle(PHColor.textPrimary)
        Text("NPS")
          .font(.caption)
          .foregroundStyle(PHColor.textTertiary)
      }
      GeometryReader { geo in
        HStack(spacing: 0) {
          segment(nps.promoters, color: PHColor.success, width: geo.size.width)
          segment(nps.passives, color: PHColor.highlight, width: geo.size.width)
          segment(nps.detractors, color: PHColor.danger, width: geo.size.width)
        }
        .clipShape(Capsule())
      }
      .frame(height: 8)
      HStack(spacing: PHSpacing.md) {
        legend("Promoters", nps.promoters, PHColor.success)
        legend("Passives", nps.passives, PHColor.highlight)
        legend("Detractors", nps.detractors, PHColor.danger)
      }
    }
    .padding(PHSpacing.sm)
    .background(PHColor.surfaceSecondary, in: RoundedRectangle(cornerRadius: PHRadius.card, style: .continuous))
  }

  private func segment(_ count: Int, color: Color, width: CGFloat) -> some View {
    let fraction = total > 0 ? CGFloat(count) / CGFloat(total) : 0
    return Rectangle()
      .fill(color)
      .frame(width: width * fraction)
  }

  private func legend(_ label: String, _ count: Int, _ color: Color) -> some View {
    HStack(spacing: 4) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text("\(label) \(count)")
        .font(.caption2)
        .foregroundStyle(PHColor.textSecondary)
    }
  }
}
