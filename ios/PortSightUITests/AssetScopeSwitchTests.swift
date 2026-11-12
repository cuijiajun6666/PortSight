//
//  AssetScopeSwitchTests.swift
//  PortSightUITests
//
//  资产 tab: switching 全部 ⌄ ↔ 量化 back and forth must not crash (it did while the charts were animating).
//

import XCTest

final class AssetScopeSwitchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRapidScopeSwitchingOnAssetsKeepsRunning() throws {
        let app = XCUIApplication()
        app.launch()
        let assets = app.tabBars.buttons["资产"]
        XCTAssertTrue(assets.waitForExistence(timeout: 10))
        assets.tap()

        for round in 0..<30 {
            let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "资产范围")).firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 5), "round \(round): scope menu missing")
            menu.tap()
            let option = topmost(app.buttons.matching(NSPredicate(format: "label == %@", round.isMultiple(of: 2) ? "量化" : "全部")))
            XCTAssertNotNil(option, "round \(round): menu item missing")
            option?.tap()
            XCTAssertEqual(app.state, .runningForeground, "crashed in round \(round)")
        }
    }

    /// The menu item, not the 全部 segment of the allocation picker further down the page.
    private func topmost(_ query: XCUIElementQuery) -> XCUIElement? {
        _ = query.firstMatch.waitForExistence(timeout: 3)
        return query.allElementsBoundByIndex.filter(\.isHittable).min { $0.frame.minY < $1.frame.minY }
    }
}
