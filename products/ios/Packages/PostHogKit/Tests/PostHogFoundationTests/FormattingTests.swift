import Foundation
import Testing

@testable import PostHogFoundation

@Suite struct MetricFormatTests {
  @Test(arguments: [
    (950.0, "950"),
    (1_500.0, "1,500"),
    (12_847.0, "12.8K"),
    (48_200.0, "48.2K"),
    (1_310_000.0, "1.3M"),
    (2_000_000_000.0, "2B"),
    (-12_500.0, "-12.5K"),
  ])
  func compactCounts(value: Double, expected: String) {
    #expect(MetricFormat.compact(value) == expected)
  }

  @Test func signedPercentUsesTypographicMinus() {
    #expect(MetricFormat.signedPercent(fraction: 0.124) == "+12.4%")
    #expect(MetricFormat.signedPercent(fraction: -0.018) == "−1.8%")
  }

  @Test(arguments: [
    (272, "4:32"),
    (59, "0:59"),
    (3_725, "1:02:05"),
  ])
  func durations(seconds: Int, expected: String) {
    #expect(MetricFormat.duration(seconds: seconds) == expected)
  }
}
