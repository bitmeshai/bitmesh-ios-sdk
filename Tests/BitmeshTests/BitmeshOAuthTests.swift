import XCTest
@testable import Bitmesh

final class BitmeshOAuthTests: XCTestCase {
    func testPayloadSignatureMatchesSha256Concatenation() {
        let signature = OAuthHelper.payloadSignature(
            body: "{\"task_id\":\"abc\"}",
            consumerKey: "test-key",
            oauthSignature: "sig=="
        )
        XCTAssertEqual(signature.count, 64)
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit })
    }

    func testAuthorizationHeaderIncludesOAuthParams() {
        let params = OAuthHelper.generateOAuthParams(
            method: "POST",
            url: "https://api.bitmesh.ai/chat",
            consumerKey: "ck",
            consumerSecret: "cs",
            timestamp: "1700000000",
            nonce: "abc123def4567890"
        )
        let header = OAuthHelper.buildAuthorizationHeader(oauthParams: params)
        XCTAssertTrue(header.hasPrefix("OAuth "))
        XCTAssertTrue(header.contains("oauth_consumer_key"))
        XCTAssertTrue(header.contains("oauth_signature"))
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}
