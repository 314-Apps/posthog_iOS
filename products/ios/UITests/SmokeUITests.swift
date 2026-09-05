import XCTest

final class SmokeUITests: XCTestCase {
  private func launch(scenario: String?) -> XCUIApplication {
    let app = XCUIApplication()
    if let scenario {
      app.launchArguments = ["-UITestScenario", scenario]
    }
    app.launch()
    return app
  }

  @MainActor
  func testSignedOutShowsWelcome() {
    let app = launch(scenario: "signedOut")
    XCTAssertTrue(app.staticTexts["PostHog"].waitForExistence(timeout: 10))
    let usCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'US Cloud'")).firstMatch
    XCTAssertTrue(usCard.exists)
    XCTAssertTrue(app.buttons["Continue"].exists)
  }

  @MainActor
  func testAPIKeySignInSheetPrefillsSelectedRegion() {
    let app = launch(scenario: "signedOut")
    let entry = app.buttons["Sign in with an API key"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10))
    entry.tap()

    let host = app.textFields.firstMatch
    XCTAssertTrue(host.waitForExistence(timeout: 5))
    XCTAssertEqual(host.value as? String, "https://us.posthog.com")
    XCTAssertTrue(app.secureTextFields.firstMatch.exists)
    // Connect stays disabled until a key that looks like one is entered.
    XCTAssertFalse(app.buttons["Connect"].isEnabled)
  }

  @MainActor
  func testSignedInHomeRendersPulse() {
    let app = launch(scenario: "signedIn")
    XCTAssertTrue(app.staticTexts["Unique users · today"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.staticTexts["Pinned dashboards"].exists)
    XCTAssertTrue(app.staticTexts["Growth overview"].waitForExistence(timeout: 10))
  }

  @MainActor
  func testDashboardDetailRendersTiles() {
    let app = launch(scenario: "signedIn")
    app.tabBars.buttons["Dashboards"].tap()
    let row = app.buttons.containing(.staticText, identifier: "Growth overview").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(app.staticTexts["Weekly signups"].waitForExistence(timeout: 15))
  }

  /// The whole drill-down chain: a number on screen, the people it counted,
  /// and one of them opened.
  @MainActor
  func testTappingANumberShowsThePeopleBehindIt() {
    let app = launch(scenario: "signedIn")
    let pulse = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Unique users today'")
    ).firstMatch
    XCTAssertTrue(pulse.waitForExistence(timeout: 15))
    pulse.tap()

    XCTAssertTrue(app.staticTexts["ada@example.com"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.staticTexts["Rowan Pike"].exists)

    app.staticTexts["ada@example.com"].tap()
    // Opening a person closes the sheet and pushes onto the tab's stack.
    XCTAssertTrue(app.buttons["Done"].waitForNonExistence(timeout: 10))
  }

  @MainActor
  func testFlagToggleRoundTrip() {
    let app = launch(scenario: "signedIn")
    app.tabBars.buttons["Flags"].tap()
    let row = app.buttons.containing(.staticText, identifier: "new-billing-flow").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    row.tap()
    XCTAssertTrue(app.staticTexts["Flag is on"].waitForExistence(timeout: 10))

    app.switches.firstMatch.tap()
    let confirm = app.buttons["Turn off flag"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
    XCTAssertTrue(app.staticTexts["Flag is off"].waitForExistence(timeout: 10))
  }
}
