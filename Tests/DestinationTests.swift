import XCTest
@testable import DMRMonitor

/// Destination model tests. These run hosted inside the real app on a
/// physical device, so they must NEVER touch UserDefaults.standard —
/// that is the user's live configuration. Every test points
/// Settings.store at a throwaway suite and wipes only that.
final class DestinationTests: XCTestCase {
    // MARK: Internal

    override func setUp() {
        super.setUp()
        let suite = UserDefaults(suiteName: Self.suiteName)!
        suite.removePersistentDomain(forName: Self.suiteName)
        Settings.store = suite
    }

    override func tearDown() {
        UserDefaults(suiteName: Self.suiteName)?
            .removePersistentDomain(forName: Self.suiteName)
        Settings.store = .standard
        super.tearDown()
    }

    func testKindNetModeRoundTrip() {
        for kind in DestinationKind.allCases {
            XCTAssertEqual(DestinationKind(netMode: kind.netMode), kind)
        }
        XCTAssertEqual(DestinationKind(netMode: "unknown"), .brandmeister,
                       "unrecognized modes fall back to BrandMeister")
    }

    func testDecodeToleratesMissingFields() throws {
        let json = #"[{"kind":"dstar"}]"#
        let list = try JSONDecoder().decode([Destination].self, from: Data(json.utf8))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].kind, .dstar)
        XCTAssertEqual(list[0].module, "B")
        XCTAssertTrue(list[0].talkgroups.isEmpty)
    }

    func testMigrationFreshInstallCreatesActiveBrandmeister() throws {
        let settings = Settings()
        XCTAssertEqual(settings.destinations.count, 1)
        let dest = try XCTUnwrap(settings.activeDestination)
        XCTAssertEqual(dest.kind, .brandmeister)
        // Fresh installs inherit the default 91/3100 talkgroup migration
        XCTAssertEqual(dest.talkgroups.map(\.tg), [91, 3_100])
    }

    func testMigrationCreatesOneDestinationPerConfiguredSystem() throws {
        let defaults = Settings.store
        defaults.set("dstar", forKey: "netMode")
        defaults.set("xlx307.duckdns.org", forKey: "dstarHost")
        defaults.set("D", forKey: "dstarModule")
        defaults.set("55553", forKey: "aslTarget")

        let settings = Settings()
        XCTAssertEqual(settings.destinations.count, 3,
                       "DMR + configured D-STAR + configured AllStar")
        let active = try XCTUnwrap(settings.activeDestination)
        XCTAssertEqual(active.kind, .dstar)
        XCTAssertEqual(active.host, "xlx307.duckdns.org")
        XCTAssertEqual(active.module, "D")
        XCTAssertEqual(settings.destinations.first { $0.kind == .allstar }?.node, "55553")
    }

    func testActivateLoadsWorkingKeysAndSnapshotsOldDestination() throws {
        let settings = Settings()
        let original = try XCTUnwrap(settings.activeDestination)

        // Mutate working state while the BM destination is active, the way
        // a net join or listen-state tap would
        settings.talkgroupList.append(Talkgroup(tg: 31_665, name: "Test"))

        var dstar = Destination(kind: .dstar)
        dstar.host = "xlx307.duckdns.org"
        dstar.module = "D"
        settings.activate(dstar)

        XCTAssertEqual(settings.netMode, "dstar")
        XCTAssertEqual(settings.dstarHost, "xlx307.duckdns.org")
        XCTAssertEqual(settings.dstarModule, "D")
        XCTAssertEqual(settings.activeDestinationID, dstar.id.uuidString)

        // The old destination's snapshot picked up the added talkgroup
        let saved = try XCTUnwrap(settings.destinations.first { $0.id == original.id })
        XCTAssertTrue(saved.talkgroups.contains { $0.tg == 31_665 })

        // Switching back restores the DMR working state
        settings.activate(saved)
        XCTAssertEqual(settings.netMode, "openterminal")
        XCTAssertTrue(settings.talkgroupList.contains { $0.tg == 31_665 })
    }

    func testDeleteActiveClearsActiveID() throws {
        let settings = Settings()
        let active = try XCTUnwrap(settings.activeDestination)
        settings.delete(active)
        XCTAssertTrue(settings.destinations.isEmpty)
        XCTAssertEqual(settings.activeDestinationID, "")
    }

    func testApplyEditsToActiveRefreshesWorkingKeys() throws {
        let settings = Settings()
        var dest = try XCTUnwrap(settings.activeDestination)
        dest.talkgroups = [Talkgroup(tg: 2, name: "Europe")]
        settings.applyEdits(dest)
        XCTAssertEqual(settings.talkgroupList.map(\.tg), [2])
    }

    func testStoreIsolationLeavesStandardDefaultsAlone() {
        // The guard this file exists for: constructing and mutating a
        // Settings must not write through to UserDefaults.standard
        let before = UserDefaults.standard.string(forKey: "netMode")
        let settings = Settings()
        settings.netMode = "dstar"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "netMode"), before)
    }

    // MARK: Private

    private static let suiteName = "com.carrierwave.DMRMonitor.DestinationTests"
}
