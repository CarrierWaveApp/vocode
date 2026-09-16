import XCTest
@testable import DMRMonitor

// MARK: - DMROptionsTests

final class DMROptionsTests: XCTestCase {
    /// FreeDMR wants one key per slot with a comma list, terminated by a
    /// semicolon. This is the form AmComm parses.
    func testFreeDMRIsCommaListWithTrailingSemicolon() {
        let options = DMROptionsDialect.freeDMR.options(talkgroups: [91, 3_100, 31_656])
        XCTAssertEqual(options, "TS2=91,3100,31656;")
    }

    /// DMR+/IPSC2 wants one key per talkgroup. The trailing semicolon is
    /// required — its own documentation calls that out as the common mistake,
    /// and the string this app sent before had no terminator at all.
    func testIndexedIsOneKeyPerTalkgroupEachTerminated() {
        let options = DMROptionsDialect.indexed.options(talkgroups: [91, 3_100])
        XCTAssertEqual(options, "TS2_1=91;TS2_2=3100;")
        XCTAssertTrue(options.hasSuffix(";"))
    }

    /// No talkgroups means no options packet rather than an empty one.
    func testEmptyTalkgroupsProduceNoOptions() {
        for dialect in [DMROptionsDialect.freeDMR, .indexed, .none] {
            XCTAssertEqual(dialect.options(talkgroups: []), "")
        }
    }

    func testNoneNeverEmitsOptions() {
        XCTAssertEqual(DMROptionsDialect.none.options(talkgroups: [91]), "")
    }

    /// AmComm runs FreeDMR — confirmed from its own dashboard, which carries
    /// the FreeDMR logo and the K0USY/HBlink credit. Sending it the indexed
    /// dialect is what made a connected link stay silent.
    func testFreeDMRFamilyNetworksMapToFreeDMR() {
        for network in ["AmComm Network", "FreeDMR Network", "FreeSTAR Network",
                        "ADN Systems", "HBLink/FreeDMR United Kingdom GB"]
        {
            XCTAssertEqual(DMROptionsDialect.forNetwork(network), .freeDMR, network)
        }
    }

    func testDMRPlusMapsToIndexed() {
        XCTAssertEqual(DMROptionsDialect.forNetwork("DMR+ IPSC2"), .indexed)
        XCTAssertEqual(DMROptionsDialect.forNetwork("DMR+ DVS IPSC2"), .indexed)
    }

    /// TGIF manages statics from its own dashboard, and options have not been
    /// verified on air there, so nothing is sent rather than something wrong.
    func testTGIFSendsNothing() {
        XCTAssertEqual(DMROptionsDialect.forNetwork("TGIF Network"), .none)
    }

    /// An unknown network, and a hand-typed host with no network at all, fall
    /// back to the broader indexed form.
    func testUnknownAndCustomFallBackToIndexed() {
        XCTAssertEqual(DMROptionsDialect.forNetwork(""), .indexed)
        XCTAssertEqual(DMROptionsDialect.forNetwork("Some Regional Net"), .indexed)
    }
}
