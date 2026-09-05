import Testing

@testable import FeatureErrors

@Suite struct FeatureErrorsSeedTests {
  @Test func moduleLinks() {
    #expect(Bool(true))
  }
}
