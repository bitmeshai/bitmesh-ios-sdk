import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import Bitmesh

/// Answers every request with a canned response and records what was sent.
final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _requests: [URLRequest] = []
    private static var _status = 200
    private static var _body = Data("{\"ok\":true}".utf8)

    static var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    /// The body a request carried. URLProtocol sees bodies as streams.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    static func reset(status: Int = 200, body: String = "{\"ok\":true}") {
        lock.lock(); defer { lock.unlock() }
        _requests = []
        _status = status
        _body = Data(body.utf8)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self._requests.append(request)
        let status = Self._status
        let body = Self._body
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class BitmeshAppCheckTests: XCTestCase {
    private struct ProviderFailure: Error {}

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    private func makeClient(
        appCheckTokenProvider: BitmeshAppCheckTokenProvider? = nil,
        debugToken: String? = nil
    ) -> BitmeshClient {
        BitmeshClient(
            apiKey: "bmk_test0123456789",
            session: .mocked,
            appCheckTokenProvider: appCheckTokenProvider,
            debugToken: debugToken
        )
    }

    private func fixtureURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bitmesh-app-check-test.m4a")
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    // MARK: - Sending the token

    func testTokenIsSentOnJSONGETAndMultipartRequests() async throws {
        let client = makeClient(appCheckTokenProvider: { "token-1" })

        _ = try await client.chat(payload: ["model": "m", "messages": []])
        _ = try await client.getVideo(id: "job-1")
        _ = try await client.transcribeFile(audioFileURL: try fixtureURL())

        let requests = MockURLProtocol.requests
        XCTAssertEqual(requests.count, 3)
        for request in requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"), "token-1", "\(request.url!.path)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bmk_test0123456789")
        }
    }

    func testTokenIsFetchedForEveryRequest() async throws {
        let counter = Counter()
        let client = makeClient(appCheckTokenProvider: { "token-\(await counter.next())" })

        _ = try await client.chat(payload: [:])
        _ = try await client.chat(payload: [:])

        XCTAssertEqual(
            MockURLProtocol.requests.map { $0.value(forHTTPHeaderField: "X-Firebase-AppCheck") },
            ["token-1", "token-2"]
        )
    }

    func testNoTokenIsSentWithoutAProvider() async throws {
        let client = makeClient()

        _ = try await client.chat(payload: [:])

        XCTAssertNil(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "X-Firebase-AppCheck"))
    }

    func testPublicResultDownloadsSendNoKeyOrToken() async throws {
        let client = makeClient(appCheckTokenProvider: { "token-1" })

        _ = try await client.getToolsResult(path: "2026-10-26/result.png")

        XCTAssertNil(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "X-Firebase-AppCheck"))
        XCTAssertNil(MockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Debug tokens

    func testDebugTokenIsSentInPlaceOfAppCheck() async throws {
        let counter = Counter()
        let client = makeClient(
            appCheckTokenProvider: { _ = await counter.next(); throw ProviderFailure() },
            debugToken: "bmdbg_abc"
        )

        _ = try await client.chat(payload: [:])

        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Bitmesh-Debug-Token"), "bmdbg_abc")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Firebase-AppCheck"))
        let calls = await counter.next()
        XCTAssertEqual(calls, 1, "the provider is not called when a debug token is set")
    }

    func testDebugTokenRejectionsExposeTheReason() {
        for reason in ["Invalid debug token", "Debug token has expired", "Debug token has reached its limit of 50 requests today (UTC)"] {
            let error = BitmeshError.httpError(statusCode: 401, body: "{\"error\":\"\(reason)\"}")
            XCTAssertEqual(error.appCheckRejectionReason, reason)
        }
    }

    // MARK: - Provider failures

    func testThrowingProviderStopsTheRequest() async {
        let client = makeClient(appCheckTokenProvider: { throw ProviderFailure() })

        do {
            _ = try await client.chat(payload: [:])
            XCTFail("Expected BitmeshAppCheckTokenError")
        } catch let error as BitmeshAppCheckTokenError {
            XCTAssertTrue(error.underlying is ProviderFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testProviderWithoutATokenStopsTheRequest() async {
        for token in [nil, "", "  "] as [String?] {
            MockURLProtocol.reset()
            let client = makeClient(appCheckTokenProvider: { token })

            do {
                _ = try await client.chat(payload: [:])
                XCTFail("Expected BitmeshAppCheckTokenError for \(String(describing: token))")
            } catch let error as BitmeshAppCheckTokenError {
                XCTAssertNil(error.underlying)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(MockURLProtocol.requests.isEmpty)
        }
    }

    // MARK: - API rejections

    func testAPIRejectionsExposeTheReason() async {
        // Messages exactly as the API's VerifyAppCheck middleware returns them.
        let reasons = [
            "Missing X-Firebase-AppCheck header",
            "App Check token is malformed",
            "App Check token signature is invalid",
            "App Check token has expired",
            "App Check token is for an unregistered app",
            "API key is not configured for App Check",
            "App Check verification is temporarily unavailable",
        ]

        for reason in reasons {
            MockURLProtocol.reset(status: 401, body: "{\"error\":\"\(reason)\"}")
            let client = makeClient(appCheckTokenProvider: { "token-1" })

            do {
                _ = try await client.chat(payload: [:])
                XCTFail("Expected a rejection for \(reason)")
            } catch let error as BitmeshError {
                guard case .httpError(401, _) = error else {
                    XCTFail("Expected httpError 401, got \(error)")
                    continue
                }
                XCTAssertEqual(error.appCheckRejectionReason, reason)
                XCTAssertEqual(error.isTemporaryAppCheckFailure, reason.contains("temporarily unavailable"), reason)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testOtherErrorsHaveNoAppCheckReason() {
        XCTAssertNil(BitmeshError.httpError(statusCode: 401, body: "{\"error\":\"Invalid API key\"}").appCheckRejectionReason)
        XCTAssertNil(BitmeshError.httpError(statusCode: 500, body: "{\"error\":\"App Check token has expired\"}").appCheckRejectionReason)
        XCTAssertNil(BitmeshError.httpError(statusCode: 401, body: "not json").appCheckRejectionReason)
        XCTAssertNil(BitmeshError.invalidJSON.appCheckRejectionReason)
    }
}

private actor Counter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

extension URLSession {
    /// A session whose requests are answered by `MockURLProtocol`.
    static var mocked: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}
