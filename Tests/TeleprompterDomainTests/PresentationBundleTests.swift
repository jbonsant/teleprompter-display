import XCTest
@testable import TeleprompterDomain

final class PresentationBundleTests: XCTestCase {
    func testStubBundleRoundTripsThroughJSON() throws {
        var bundle = PresentationBundle.stub(source: "presentation-script.md", rawScript: "# GPSN\nBonjour")
        bundle.generatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PresentationBundle.self, from: data)

        XCTAssertEqual(decoded, bundle)
    }

    func testSessionStateIncludesLiveModes() {
        XCTAssertTrue(SessionState.allCases.contains(.liveAuto))
        XCTAssertTrue(SessionState.allCases.contains(.manualScroll))
        XCTAssertTrue(SessionState.allCases.contains(.recoveringLocal))
    }
}
