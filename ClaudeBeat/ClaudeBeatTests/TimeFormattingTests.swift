import XCTest
@testable import ClaudeBeat

final class TimeFormattingTests: XCTestCase {

    func testMenuBarFormat_hours() {
        let future = Date().addingTimeInterval(2 * 3600 + 14 * 60)
        let result = TimeFormatting.menuBarString(until: future)
        XCTAssertEqual(result, "2h")
    }

    func testMenuBarFormat_minutes() {
        let future = Date().addingTimeInterval(45 * 60)
        let result = TimeFormatting.menuBarString(until: future)
        XCTAssertEqual(result, "45m")
    }

    func testMenuBarFormat_lessThanOneMinute() {
        let future = Date().addingTimeInterval(30)
        let result = TimeFormatting.menuBarString(until: future)
        XCTAssertEqual(result, "<1m")
    }

    func testMenuBarFormat_past() {
        let past = Date().addingTimeInterval(-60)
        let result = TimeFormatting.menuBarString(until: past)
        XCTAssertEqual(result, "now")
    }

    func testPopoverFormat_hoursAndMinutes() {
        let future = Date().addingTimeInterval(2 * 3600 + 14 * 60)
        let result = TimeFormatting.popoverString(until: future)
        XCTAssertEqual(result, "2h 14m")
    }

    func testPopoverFormat_minutesOnly() {
        let future = Date().addingTimeInterval(45 * 60 + 30)
        let result = TimeFormatting.popoverString(until: future)
        XCTAssertEqual(result, "45m")
    }

    func testPopoverFormat_dateForFarFuture() {
        let future = Date().addingTimeInterval(3 * 24 * 3600)
        let result = TimeFormatting.popoverString(until: future)
        // Should show a date like "Apr 10" instead of hours
        XCTAssertFalse(result.contains("h"))
    }
}
