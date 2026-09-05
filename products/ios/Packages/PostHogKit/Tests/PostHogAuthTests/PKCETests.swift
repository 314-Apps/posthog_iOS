import Foundation
import Testing

@testable import PostHogAuth

@Suite struct PKCETests {
  @Test func matchesRFC7636AppendixBVector() {
    let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    #expect(PKCEPair.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  }

  @Test func verifierIsBase64URLWithoutPadding() {
    let pair = PKCEPair()
    #expect(pair.verifier.count >= 43)
    #expect(!pair.verifier.contains("+"))
    #expect(!pair.verifier.contains("/"))
    #expect(!pair.verifier.contains("="))
    #expect(pair.challenge == PKCEPair.challenge(for: pair.verifier))
  }

  @Test func pairsAreUnique() {
    #expect(PKCEPair().verifier != PKCEPair().verifier)
  }
}
