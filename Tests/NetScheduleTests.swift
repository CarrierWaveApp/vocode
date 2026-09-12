@testable import DMRMonitor
import XCTest

final class NetScheduleTests: XCTestCase {
    private func utcDate(_ year: Int, _ month: Int, _ day: Int,
                         _ hour: Int, _ minute: Int) -> Date
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func net(weekdays: [Int], hour: Int, minute: Int,
                     zone: String) -> Net
    {
        Net(name: "Test", talkgroup: 3100, weekdays: weekdays,
            hour: hour, minute: minute, timeZoneID: zone)
    }

    func testDstSpringForwardKeepsWallClock() {
        // US DST began 2026-03-08 in Denver. A Sunday 19:00 Denver net:
        // before the change 19:00 MST = 02:00Z, after 19:00 MDT = 01:00Z.
        let denver = net(weekdays: [1], hour: 19, minute: 0,
                         zone: "America/Denver")
        // Saturday Mar 7, noon UTC -> next occurrence Sunday Mar 8
        let before = utcDate(2026, 3, 7, 12, 0)
        let start = NetSchedule.nextOccurrence(of: denver, after: before)
        XCTAssertEqual(start, utcDate(2026, 3, 9, 1, 0),
                       "spring-forward Sunday 19:00 MDT is 01:00Z Monday")
    }

    func testUtcNetCrossingLocalDayBoundary() {
        // A Tuesday 01:00Z net is Monday evening in the US; the weekday
        // must be evaluated in the net's zone, not the device's
        let utc = net(weekdays: [3], hour: 1, minute: 0, zone: "UTC")
        let monday = utcDate(2026, 9, 7, 12, 0)
        let start = NetSchedule.nextOccurrence(of: utc, after: monday)
        XCTAssertEqual(start, utcDate(2026, 9, 8, 1, 0))
    }

    func testMultiWeekdayPicksSoonest() {
        // Mon + Fri net, asked on a Wednesday -> Friday wins over Monday
        let multi = net(weekdays: [2, 6], hour: 12, minute: 0, zone: "UTC")
        let wednesday = utcDate(2026, 9, 9, 0, 0)
        let start = NetSchedule.nextOccurrence(of: multi, after: wednesday)
        XCTAssertEqual(start, utcDate(2026, 9, 11, 12, 0))
    }

    func testOccurrencesAdvance() {
        let weekly = net(weekdays: [4], hour: 12, minute: 0, zone: "UTC")
        let dates = NetSchedule.occurrences(
            of: weekly, after: utcDate(2026, 9, 7, 0, 0), limit: 3
        )
        XCTAssertEqual(dates.count, 3)
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 7 * 86400)
        XCTAssertEqual(dates[2].timeIntervalSince(dates[1]), 7 * 86400)
    }

    func testLeadRollsToPreviousWeekday() throws {
        // 00:05 Sunday start with a 10-minute lead fires Saturday 23:55;
        // the scheduler derives components from the concrete fire date
        let early = net(weekdays: [1], hour: 0, minute: 5, zone: "UTC")
        let start = try XCTUnwrap(NetSchedule.nextOccurrence(
            of: early, after: utcDate(2026, 9, 9, 0, 0)
        ))
        let fire = start.addingTimeInterval(-600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let comps = calendar.dateComponents(
            [.weekday, .hour, .minute], from: fire
        )
        XCTAssertEqual(comps.weekday, 7)
        XCTAssertEqual(comps.hour, 23)
        XCTAssertEqual(comps.minute, 55)
    }

    func testIsLiveWindow() {
        let weekly = net(weekdays: [4], hour: 12, minute: 0, zone: "UTC")
        XCTAssertTrue(NetSchedule.isLive(weekly, at: utcDate(2026, 9, 9, 12, 30)))
        XCTAssertFalse(NetSchedule.isLive(weekly, at: utcDate(2026, 9, 9, 13, 30)))
        XCTAssertFalse(NetSchedule.isLive(weekly, at: utcDate(2026, 9, 9, 11, 59)))
    }

    func testLenientDecodeAndEnvelopeFallback() {
        let bare = Data(#"[{"name":"X","talkgroup":91,"weekdays":[2]}]"#.utf8)
        let nets = try? JSONDecoder().decode([Net].self, from: bare)
        XCTAssertEqual(nets?.first?.talkgroup, 91)
        XCTAssertEqual(nets?.first?.leads, [10])
        XCTAssertEqual(nets?.first?.enabled, true)
    }

    func testCountdownFormats() {
        let now = utcDate(2026, 9, 9, 12, 0)
        XCTAssertEqual(NetSchedule.countdown(
            to: now.addingTimeInterval(300), from: now
        ), "in 5m")
        XCTAssertEqual(NetSchedule.countdown(
            to: now.addingTimeInterval(5400), from: now
        ), "in 1h 30m")
        XCTAssertEqual(NetSchedule.countdown(to: now, from: now), "now")
    }
}
