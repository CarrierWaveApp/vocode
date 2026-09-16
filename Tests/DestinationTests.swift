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

    // MARK: - Homebrew network selection

    /// Destinations saved before the network fields existed must still
    /// decode, landing on manual (no network) rather than auto-picking.
    func testDecodeToleratesMissingNetworkFields() throws {
        let json = #"[{"kind":"hotspot","host":"3103.amcomm.network","port":62031}]"#
        let list = try JSONDecoder().decode([Destination].self, from: Data(json.utf8))
        XCTAssertEqual(list[0].network, "")
        XCTAssertEqual(list[0].networkPassword, "")
    }

    /// Activating a Homebrew destination loads the network and its password
    /// into the working keys, and snapshotting carries them back.
    func testHomebrewNetworkRoundTripsThroughWorkingKeys() throws {
        let settings = Settings()
        var dest = Destination(kind: .hotspot, name: "AmComm")
        dest.network = "AmComm Network"
        dest.networkPassword = "Passw0rd"
        dest.autoMaster = true
        settings.activate(dest)
        XCTAssertEqual(settings.hbNetwork, "AmComm Network")
        XCTAssertEqual(settings.hbPassword, "Passw0rd")
        XCTAssertTrue(settings.autoMaster)

        // The connect-time probe rewrites the working host; it must survive.
        settings.host = "3105.amcomm.network"
        settings.port = 62_031
        settings.snapshotActiveDestination()
        let saved = try XCTUnwrap(settings.activeDestination)
        XCTAssertEqual(saved.host, "3105.amcomm.network")
        XCTAssertEqual(saved.network, "AmComm Network")
        XCTAssertEqual(saved.networkPassword, "Passw0rd")
    }

    /// The network's published password is used when there is one, and the
    /// operator's own only when the network demands it.
    func testHomebrewConfigPrefersNetworkPassword() throws {
        let settings = Settings()
        settings.callsign = "N0CALL"
        settings.dmrID = "3101234"
        settings.suffix = "01"
        settings.host = "3103.amcomm.network"
        settings.port = 62_031

        settings.password = "my-selfcare-key"
        settings.hbPassword = "Passw0rd"
        XCTAssertEqual(try XCTUnwrap(settings.homebrewConfig).password, "Passw0rd")

        // A network listing a literal PASSWORD leaves hbPassword empty.
        settings.hbPassword = ""
        XCTAssertEqual(try XCTUnwrap(settings.homebrewConfig).password, "my-selfcare-key")
    }

    /// With neither password there is nothing to authenticate with, so the
    /// connect path must refuse rather than send an empty credential.
    func testHomebrewConfigNilWithoutAnyPassword() {
        let settings = Settings()
        settings.callsign = "N0CALL"
        settings.dmrID = "3101234"
        settings.host = "3103.amcomm.network"
        settings.password = ""
        settings.hbPassword = ""
        XCTAssertNil(settings.homebrewConfig)
    }

    // MARK: - Connected server detail

    /// The server is secondary detail under the destination's name. On
    /// BrandMeister it reads as the master's own id and country — this is the
    /// string that used to replace "BrandMeister" in the title bar.
    func testConnectedServerNamesTheBrandMeisterServer() {
        let settings = Settings()
        settings.netMode = "openterminal"
        settings.host = "3341.master.brandmeister.network"
        XCTAssertEqual(settings.connectedServer, "3341 Mexico")
    }

    /// An unlisted BrandMeister host still names itself rather than vanishing.
    func testConnectedServerFallsBackToHost() {
        let settings = Settings()
        settings.netMode = "openterminal"
        settings.host = "master.example.org"
        XCTAssertEqual(settings.connectedServer, "master.example.org")
    }

    /// Homebrew ports vary by network, so the port is worth showing and
    /// matches what the connection log prints.
    func testConnectedServerIncludesHomebrewPort() {
        let settings = Settings()
        settings.netMode = "homebrew"
        settings.host = "3105.amcomm.network"
        settings.port = 62_031
        XCTAssertEqual(settings.connectedServer, "3105.amcomm.network:62031")
    }

    /// For AllStar and D-STAR the node and reflector module are the
    /// destination itself, so there is no second line to draw.
    func testConnectedServerNilWhereItWouldRepeatTheName() {
        let settings = Settings()
        for mode in ["allstar", "dstar"] {
            settings.netMode = mode
            XCTAssertNil(settings.connectedServer, mode)
        }
        settings.netMode = "homebrew"
        settings.host = ""
        XCTAssertNil(settings.connectedServer)
    }

    /// The name shown while connected comes from the destination, so a custom
    /// name wins and an automatic destination falls back to its network.
    func testDisplayNamePrefersCustomThenNetwork() {
        var named = Destination(kind: .hotspot, name: "Shack")
        named.network = "AmComm Network"
        named.autoMaster = true
        XCTAssertEqual(named.displayName, "Shack")

        var unnamed = Destination(kind: .hotspot)
        unnamed.network = "AmComm Network"
        unnamed.autoMaster = true
        XCTAssertEqual(unnamed.displayName, "AmComm Network")

        var auto = Destination(kind: .brandmeister)
        auto.autoMaster = true
        XCTAssertEqual(auto.displayName, "BrandMeister")
    }

    // MARK: Private

    private static let suiteName = "com.carrierwave.DMRMonitor.DestinationTests"
}
