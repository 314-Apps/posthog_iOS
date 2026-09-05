import Testing

@testable import FeatureLive

@Suite struct FeatureLiveSeedTests {
  @Test func moduleLinks() {
    #expect(Bool(true))
  }
}
