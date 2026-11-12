import XCTest

final class DesktopSidebarTooltipTests: XCTestCase {
    @MainActor
    func testNativeTooltipsBeforeAndAfterSelectionChanges() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["nav_overview"].waitForExistence(timeout: 15))

        // Cover the initially selected item and every initially inactive item.
        assertSelected(app.buttons["nav_overview"])
        let rail = ["overview": "总览", "assets": "资产", "trading": "交易", "backtest": "回测",
                    "server": "服务器", "cloud": "云盘", "ai": "AI", "remote": "远程"]
        for (id, title) in rail {
            assertTooltip(app, button: app.buttons["nav_" + id], title: title)
        }

        // Cross several rows, then test both the new selection and the old one.
        app.buttons["nav_server"].click()
        assertSelected(app.buttons["nav_server"])
        XCTAssertNotEqual(app.buttons["nav_overview"].value as? String, "已选择")
        assertTooltip(app, button: app.buttons["nav_server"], title: "服务器")
        assertTooltip(app, button: app.buttons["nav_overview"], title: "总览")

        app.buttons["nav_overview"].click()
        assertSelected(app.buttons["nav_overview"])
        assertTooltip(app, button: app.buttons["nav_overview"], title: "总览")
        assertTooltip(app, button: app.buttons["nav_server"], title: "服务器")
        XCTAssertFalse(app.buttons["侧栏设置"].exists)
        assertTooltip(app, button: app.buttons["toolbar_settings"], title: "设置")
    }

    @MainActor
    private func assertSelected(_ button: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "已选择"), object: button
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    @MainActor
    private func assertTooltip(_ app: XCUIApplication, button: XCUIElement, title: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        // Leave the rail so a previous tooltip cannot satisfy the next check.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).hover()
        let tooltip = app.helpTags.firstMatch
        XCTAssertTrue(tooltip.waitForNonExistence(timeout: 5), "Previous tooltip did not dismiss", file: file, line: line)
        XCTAssertTrue(button.isHittable, "Sidebar button is not hittable: " + title, file: file, line: line)

        button.hover()
        // Observe an actual system help tag, not the button's accessibility help string.
        XCTAssertTrue(tooltip.waitForExistence(timeout: 8), "No visible system tooltip for " + title, file: file, line: line)
        let text = NSPredicate(format: "label == %@ OR value == %@", title, title)
        let matchingTag = app.helpTags.matching(text).firstMatch
        let matchingChild = tooltip.descendants(matching: .any).matching(text).firstMatch
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in matchingTag.exists || matchingChild.exists }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed,
                       "Tooltip text does not match " + title, file: file, line: line)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Sidebar tooltip — " + title + " — " + (button.value as? String ?? "未选择")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
