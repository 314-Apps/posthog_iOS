import Testing

@testable import FeatureExperiments

@Suite struct FeatureExperimentsSeedTests {
  @Test func moduleLinks() {
    #expect(Bool(true))
  }
}
