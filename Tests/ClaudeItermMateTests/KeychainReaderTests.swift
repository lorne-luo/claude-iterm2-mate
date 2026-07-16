import XCTest
@testable import ClaudeItermMate

final class KeychainReaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000) // 1e6 s = 1e9 ms

    func testParsesValidUnexpiredToken() {
        let json = """
        {"claudeAiOauth":{"accessToken":"tok-123","expiresAt":2000000000}}
        """.data(using: .utf8)! // expiresAt 2e9 ms > 1e9 ms now
        XCTAssertEqual(KeychainReader.parseAccessToken(json: json, now: now), "tok-123")
    }

    func testMissingTokenIsNil() {
        let json = """
        {"claudeAiOauth":{"expiresAt":2000000000}}
        """.data(using: .utf8)!
        XCTAssertNil(KeychainReader.parseAccessToken(json: json, now: now))
    }

    func testExpiredTokenIsNil() {
        let json = """
        {"claudeAiOauth":{"accessToken":"tok-123","expiresAt":500000000}}
        """.data(using: .utf8)! // expiresAt 5e8 ms < 1e9 ms now
        XCTAssertNil(KeychainReader.parseAccessToken(json: json, now: now))
    }

    func testTokenWithoutExpiryIsAccepted() {
        let json = """
        {"claudeAiOauth":{"accessToken":"tok-123"}}
        """.data(using: .utf8)!
        XCTAssertEqual(KeychainReader.parseAccessToken(json: json, now: now), "tok-123")
    }

    func testMalformedJsonIsNil() {
        XCTAssertNil(KeychainReader.parseAccessToken(json: Data("nope".utf8), now: now))
    }

    func testReadTokenUsesInjectedSecurityOutput() {
        let json = Data("""
        {"claudeAiOauth":{"accessToken":"tok-xyz","expiresAt":2000000000}}
        """.utf8)
        let token = KeychainReader.readToken(now: now, runSecurity: { json })
        XCTAssertEqual(token, "tok-xyz")
    }

    func testReadTokenNilWhenSecurityFails() {
        XCTAssertNil(KeychainReader.readToken(now: now, runSecurity: { nil }))
    }
}
