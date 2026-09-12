import XCTest
@testable import DMRMonitor

// MARK: - ASLDirectoryTests

final class ASLDirectoryTests: XCTestCase {
    func testDoHTXTParsing() {
        let json = """
        {"Status":0,"Answer":[{"name":"2000.nodes.allstarlink.org","type":16,"TTL":60,
        "data":"\\"NN=2000\\" \\"IP=18.224.69.177\\" \\"PT=4569\\""}]}
        """
        let parsed = ASLDirectory.parseDoHTXT(Data(json.utf8))
        XCTAssertEqual(parsed?.host, "18.224.69.177")
        XCTAssertEqual(parsed?.port, 4_569)
    }

    func testDoHTXTParsingNoAnswer() {
        XCTAssertNil(ASLDirectory.parseDoHTXT(Data("{\"Status\":3}".utf8)))
        XCTAssertNil(ASLDirectory.parseDoHTXT(Data("not json".utf8)))
    }
}
