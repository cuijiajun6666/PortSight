import XCTest

final class PortsightMacUITests: XCTestCase {
    @MainActor
    func testPortfolioMetricsAndIconNavigation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["nav_assets"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["sidebar_toggle"].exists)
        app.buttons["nav_assets"].click()
        let value = app.staticTexts["portfolio_value"]
        XCTAssertTrue(value.waitForExistence(timeout: 15))
        assertValue(value, equals: "$80,350.00")
        let scope = app.radioGroups["portfolio_scope"]
        scope.radioButtons["个人"].click()
        XCTAssertTrue(value.waitForExistence(timeout: 3))
        assertValue(value, equals: "$25,200.00")
        app.buttons["收益率"].click()
        assertValue(value, equals: "+7.69%")
        scope.radioButtons["量化"].click()
        app.buttons["金额"].click()
        assertValue(value, equals: "$55,150.00")
        // Holdings sit in the second tab group of the 资产 top bar.
        app.radioGroups["section_tabs_1"].radioButtons["持仓"].click()
        XCTAssertTrue(app.textFields["position_search"].waitForExistence(timeout: 5))
        app.radioGroups["section_tabs_0"].radioButtons["概览"].click()
        scope.radioButtons["全部"].click()
        assertValue(value, equals: "$80,350.00")
    }

    @MainActor
    private func assertValue(_ element: XCUIElement, equals expected: String, file: StaticString = #filePath, line: UInt = #line) {
        // macOS exposes Text content as AXValue; iOS exposes it as AXLabel.
        let predicate = NSPredicate(format: "value == %@ OR label == %@", expected, expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }
}
