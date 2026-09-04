import XCTest

final class SmokeUITests: XCTestCase {
  @MainActor
  func testColdLaunchShowsRoot() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.staticTexts["PostHog"].waitForExistence(timeout: 10))
  }
}
