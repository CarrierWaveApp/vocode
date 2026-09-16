import XCTest
@testable import DMRMonitor

// MARK: - HomebrewScoutTests

final class HomebrewScoutTests: XCTestCase {
    /// `RPTL` then the DMR ID as four big-endian bytes. Getting the byte
    /// order wrong here would still "work" against a master that NAKs
    /// everything, so pin it.
    func testLoginFrameIsRPTLPlusBigEndianID() {
        XCTAssertEqual(Array(HomebrewScout.loginFrame(dmrID: 0)),
                       Array("RPTL".utf8) + [0x00, 0x00, 0x00, 0x00])
        // 3_101_234 == 0x002F5232
        XCTAssertEqual(Array(HomebrewScout.loginFrame(dmrID: 3_101_234)),
                       Array("RPTL".utf8) + [0x00, 0x2F, 0x52, 0x32])
    }

    /// The probe must never carry a real DMR ID: networks route on the ID,
    /// so a probe with the operator's own would risk dropping their hotspot.
    func testProbeIDIsUnregistered() {
        XCTAssertEqual(HomebrewScout.probeID, 0)
    }

    /// Both replies observed in the wild count as alive. `MSTNAK` comes from
    /// masters that validate the ID up front, `RPTACK` plus a 4-byte salt
    /// from ones that challenge first — these are captured bytes.
    func testAcceptsBothLiveReplies() {
        XCTAssertTrue(HomebrewScout.isLiveReply(Data("MSTNAK".utf8) + Data([0, 0, 0, 0])))
        XCTAssertTrue(HomebrewScout.isLiveReply(Data("RPTACK".utf8) + Data([0x4E, 0x94, 0xE9, 0x92])))
    }

    func testRejectsNonReplies() {
        XCTAssertFalse(HomebrewScout.isLiveReply(nil))
        XCTAssertFalse(HomebrewScout.isLiveReply(Data()))
        XCTAssertFalse(HomebrewScout.isLiveReply(Data("RPT".utf8)))
        XCTAssertFalse(HomebrewScout.isLiveReply(Data("HTTP/1.1 404".utf8)))
    }

    /// An empty sweep must still call back rather than leaving the caller
    /// waiting on a completion that never fires.
    @MainActor
    func testEmptySweepCompletesImmediately() {
        let scout = HomebrewScout()
        let done = expectation(description: "completion")
        scout.probeAll([]) { result in
            XCTAssertNil(result)
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
    }

    /// A bad port can't open a socket; the sweep must still settle.
    @MainActor
    func testUnusablePortStillSettles() {
        let scout = HomebrewScout()
        let host = DMRHost(name: "FD_Test", network: "Test", host: "127.0.0.1",
                           password: "passw0rd", port: 0)
        let done = expectation(description: "completion")
        scout.probeAll([host]) { result in
            XCTAssertNil(result)
            done.fulfill()
        }
        // Generous: if the socket opens at all, the 2.5 s probe timeout is
        // the backstop that settles it.
        wait(for: [done], timeout: 5)
        XCTAssertEqual(scout.results[host.id], .unreachable)
    }
}
