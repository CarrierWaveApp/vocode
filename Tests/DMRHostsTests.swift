import XCTest
@testable import DMRMonitor

// MARK: - DMRHostsTests

final class DMRHostsTests: XCTestCase {
    /// Section headers name every entry beneath them, and the real file mixes
    /// CRLF with LF — a split that keeps the \r would break the port field.
    func testParsesSectionsAndCRLF() {
        let text = "#\t\tAmComm Network Hosts Below\r\n"
            + "FD_AmComm_Chicago\t3103\t3103.amcomm.network\tPassw0rd\t62031\r\n"
            + "#\t\tTGIF Network Hosts Below\n"
            + "TGIF_Network\t0000\ttgif.network\tpassw0rd\t62031\n"
        let hosts = DMRHostsDirectory.parse(text)
        XCTAssertEqual(hosts.count, 2)
        XCTAssertEqual(hosts[0].network, "AmComm Network")
        XCTAssertEqual(hosts[0].host, "3103.amcomm.network")
        XCTAssertEqual(hosts[0].port, 62_031)
        XCTAssertEqual(hosts[0].password, "Passw0rd")
        XCTAssertEqual(hosts[1].network, "TGIF Network")
    }

    /// BrandMeister prohibits radioless HBP clients, so its masters must not
    /// reach a Homebrew picker — by name prefix or by section.
    func testDropsBrandMeisterAndLoopback() {
        let text = "#\t\tBrandMeister Hosts Below\n"
            + "BM_2041_Netherlands\t2041\t2041.master.brandmeister.network\tpassw0rd\t62031\n"
            + "#\t\tDMRGateway / Internal Hosts Below\n"
            + "DMRGateway\t0000\t127.0.0.1\tnone\t62031\n"
            + "#\t\tAmComm Network Hosts Below\n"
            + "FD_AmComm_Dallas\t3104\t3104.amcomm.network\tPassw0rd\t62031\n"
        let hosts = DMRHostsDirectory.parse(text)
        XCTAssertEqual(hosts.map(\.host), ["3104.amcomm.network"])
    }

    /// The same endpoint listed twice is one destination; distinct hostnames
    /// are not, even when they resolve to one box.
    func testDeduplicatesByEndpointOnly() {
        let text = "#\t\tAmComm Network Hosts Below\n"
            + "FD_AmComm_Atlanta\t3102\t3102.amcomm.network\tPassw0rd\t62031\n"
            + "FD_AmComm_Atlanta_Copy\t3102\t3102.amcomm.network\tPassw0rd\t62031\n"
            + "FD_AmComm_Miami_FL\t3106\t3106.amcomm.network\tPassw0rd\t62031\n"
        let hosts = DMRHostsDirectory.parse(text)
        XCTAssertEqual(hosts.count, 2)
        XCTAssertEqual(hosts.map(\.host), ["3102.amcomm.network", "3106.amcomm.network"])
    }

    /// A literal `PASSWORD` means the network wants your own; anything else
    /// is a shared default we can connect with unattended.
    func testPasswordPlaceholderDetection() {
        let text = "#\t\tHBLink/FreeDMR Belgium BE Hosts Below\n"
            + "HB_BE_OpenDMR_master\t0000\thotspots.odmr.be\tGuru4me!\t62031\n"
            + "HB_AU_VKMulti_DMO\t0000\tvkmulti.net\tPASSWORD\t62031\n"
        let hosts = DMRHostsDirectory.parse(text)
        XCTAssertFalse(hosts[0].needsOwnPassword)
        XCTAssertTrue(hosts[1].needsOwnPassword)
    }

    func testLabelStripsFileBookkeepingPrefix() {
        let text = "#\t\tAmComm Network Hosts Below\n"
            + "FD_AmComm_New_Jersey\t3108\t3108.amcomm.network\tPassw0rd\t62031\n"
            + "#\t\tFreeDMR Network Hosts Below\n"
            + "FreeDMR_Argentina\t7222\tfreedmr.rmdv.org\tpassw0rd\t62031\n"
        let hosts = DMRHostsDirectory.parse(text)
        XCTAssertEqual(hosts[0].label, "AmComm New Jersey")
        XCTAssertEqual(hosts[1].label, "FreeDMR Argentina")
    }

    func testIgnoresMalformedLines() {
        let text = "#\t\tAmComm Network Hosts Below\n"
            + "truncated\tline\n"
            + "FD_AmComm_Bad_Port\t3104\t3104.amcomm.network\tPassw0rd\tnotaport\n"
            + "\n"
            + "FD_AmComm_Dallas\t3104\t3104.amcomm.network\tPassw0rd\t62031\n"
        XCTAssertEqual(DMRHostsDirectory.parse(text).map(\.host), ["3104.amcomm.network"])
    }

    /// The bundled snapshot must survive the real parser — this is the guard
    /// against a host-file format change landing silently.
    func testBundledSnapshotParses() throws {
        // The snapshot ships with the app target; when the test bundle is
        // hosted, Bundle.main is that app. Check both.
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "DMR_Hosts", withExtension: "txt")
            ?? Bundle.main.url(forResource: "DMR_Hosts", withExtension: "txt"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let hosts = DMRHostsDirectory.parse(text)
        XCTAssertGreaterThan(hosts.count, 300)
        XCTAssertFalse(hosts.contains { $0.host.contains("brandmeister") })
        XCTAssertTrue(hosts.contains { $0.network.contains("AmComm") })
        XCTAssertTrue(hosts.allSatisfy { $0.port > 0 })
    }
}
