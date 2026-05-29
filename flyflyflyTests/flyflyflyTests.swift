import XCTest
@testable import flyflyfly

final class TunnelOutputParserTests: XCTestCase {
    func testEndpointParsesRSDAddressAndPortOutput() {
        let output = """
        RSD Address: fd7b:e5b:6f53::1
        RSD Port: 51234
        """

        let endpoint = TunnelOutputParser.endpoint(in: output)

        XCTAssertEqual(endpoint?.host, "fd7b:e5b:6f53::1")
        XCTAssertEqual(endpoint?.port, "51234")
    }

    func testEndpointParsesJSONOutput() {
        let output = #"{"host":"127.0.0.1","port":64321}"#

        let endpoint = TunnelOutputParser.endpoint(in: output)

        XCTAssertEqual(endpoint?.host, "127.0.0.1")
        XCTAssertEqual(endpoint?.port, "64321")
    }

    func testEndpointUsesLastScriptModeEndpoint() {
        let output = """
        booting tunnel
        localhost 50001
        still probing
        192.168.0.8 50002
        """

        let endpoint = TunnelOutputParser.endpoint(in: output)

        XCTAssertEqual(endpoint?.host, "192.168.0.8")
        XCTAssertEqual(endpoint?.port, "50002")
    }

    func testEndpointParsesLastRSDCommandArguments() {
        let output = """
        retrying --rsd 127.0.0.1 60001
        selected --rsd 127.0.0.1 60002
        """

        let endpoint = TunnelOutputParser.endpoint(in: output)

        XCTAssertEqual(endpoint?.host, "127.0.0.1")
        XCTAssertEqual(endpoint?.port, "60002")
    }

    func testImmediateFailureDetectsPrivilegeError() {
        let failure = TunnelOutputParser.immediateFailure(in: "requires root privileges")

        XCTAssertEqual(failure, "This command requires root privileges. Consider retrying with \"sudo\".")
    }

    func testImmediateFailureIgnoresBoxDrawingLinesAndReturnsLastFatalLine() {
        let output = """
        ╭────────────╮
        │ status     │
        warning: still trying
        connection refused by remote endpoint
        """

        let failure = TunnelOutputParser.immediateFailure(in: output)

        XCTAssertEqual(failure, "connection refused by remote endpoint")
    }
}

final class CoordinateParserTests: XCTestCase {
    func testParseAcceptsCommaSeparatedCoordinates() throws {
        let coordinate = try XCTUnwrap(CoordinateParser.parse("25.033, 121.565"))

        XCTAssertEqual(coordinate.latitude, 25.033, accuracy: 0.000_001)
        XCTAssertEqual(coordinate.longitude, 121.565, accuracy: 0.000_001)
    }

    func testParseAcceptsChineseCommaAndWhitespace() throws {
        let coordinate = try XCTUnwrap(CoordinateParser.parse("25.033 ， 121.565"))

        XCTAssertEqual(coordinate.latitude, 25.033, accuracy: 0.000_001)
        XCTAssertEqual(coordinate.longitude, 121.565, accuracy: 0.000_001)
    }

    func testParseRejectsOutOfRangeCoordinatesButStillRecognizesTheShape() {
        XCTAssertNil(CoordinateParser.parse("999, 999"))
        XCTAssertTrue(CoordinateParser.isCoordinateLike("999, 999"))
    }

    func testParseRejectsNonCoordinateText() {
        XCTAssertNil(CoordinateParser.parse("Taipei 101"))
        XCTAssertFalse(CoordinateParser.isCoordinateLike("Taipei 101"))
    }
}
