import Foundation
import XCTest
@testable import Bitmesh

final class BitmeshRealtimeTests: XCTestCase {
    func testParsesBeginTurnAndTermination() throws {
        guard case .begin(let begin) = RealtimeTranscriptionEvent(json: ["type": "Begin", "id": "sess_1", "expires_at": 1794471255]) else {
            return XCTFail("Expected begin")
        }
        XCTAssertEqual(begin.id, "sess_1")
        XCTAssertEqual(begin.expiresAt, Date(timeIntervalSince1970: 1794471255))

        guard case .turn(let turn) = RealtimeTranscriptionEvent(json: [
            "type": "Turn",
            "turn_order": 2,
            "end_of_turn": true,
            "turn_is_formatted": true,
            "transcript": "Smoke from hundreds of wildfires.",
            "language_code": "en",
            "language_confidence": 0.98,
            "words": [["text": "Smoke", "start": 0, "end": 300]],
        ]) else {
            return XCTFail("Expected turn")
        }
        XCTAssertEqual(turn.turnOrder, 2)
        XCTAssertTrue(turn.endOfTurn)
        XCTAssertTrue(turn.isFormatted)
        XCTAssertEqual(turn.transcript, "Smoke from hundreds of wildfires.")
        XCTAssertEqual(turn.languageCode, "en")
        XCTAssertEqual(turn.languageConfidence, 0.98)
        XCTAssertEqual(turn.words.first?["text"] as? String, "Smoke")

        guard case .termination(let end) = RealtimeTranscriptionEvent(json: [
            "type": "Termination", "audio_duration_seconds": 20, "session_duration_seconds": 21,
        ]) else {
            return XCTFail("Expected termination")
        }
        XCTAssertEqual(end.audioDurationSeconds, 20)
        XCTAssertEqual(end.sessionDurationSeconds, 21)
    }

    func testUnknownMessagesAreKept() {
        let event = RealtimeTranscriptionEvent(json: ["type": "SpeechStarted", "x": 1])
        guard case .other(let type, let raw) = event else {
            return XCTFail("Expected other")
        }
        XCTAssertEqual(type, "SpeechStarted")
        XCTAssertEqual(raw["x"] as? Int, 1)
        XCTAssertEqual(event.raw["type"] as? String, "SpeechStarted")
    }

    func testWebSocketURL() throws {
        XCTAssertEqual(
            try BitmeshClient.webSocketURL(URL(string: "https://api.bitmesh.ai/v2/transcribe-realtime?sample_rate=16000")).absoluteString,
            "wss://api.bitmesh.ai/v2/transcribe-realtime?sample_rate=16000"
        )
        XCTAssertEqual(
            try BitmeshClient.webSocketURL(URL(string: "http://localhost:8003/v2/transcribe-realtime")).absoluteString,
            "ws://localhost:8003/v2/transcribe-realtime"
        )
    }

    func testClosedError() {
        let error = BitmeshRealtimeClosedError(code: 3008, reason: "Session reached its time limit")
        XCTAssertTrue(error.isTimeLimit)
        XCTAssertEqual(error.errorDescription, "Real-time transcription closed with code 3008: Session reached its time limit")
    }

    func testSampleRateMustBePositive() async {
        let client = BitmeshClient(apiKey: "bmk_test")
        do {
            _ = try await client.transcribeRealtime(sampleRate: 0)
            XCTFail("Expected a validation error")
        } catch BitmeshError.validation(let message) {
            XCTAssertEqual(message, "sampleRate must be positive.")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Live API

    private static func requireWebSockets() throws {
        #if canImport(FoundationNetworking)
        try XCTSkipIf(true, "URLSession can't open WebSockets on Linux.")
        #endif
    }

    /// Streams BITMESH_TEST_AUDIO_PCM (16 kHz 16-bit mono PCM) to the live API.
    /// Billed: a 20 s clip on universal-streaming-english costs about 0.002.
    func testRealtimeSessionTranscribesStreamedAudio() async throws {
        try Self.requireWebSockets()
        let client = try BitmeshTestSupport.makeClient()
        guard let path = ProcessInfo.processInfo.environment["BITMESH_TEST_AUDIO_PCM"], !path.isEmpty else {
            throw XCTSkip("Set BITMESH_TEST_AUDIO_PCM to a 16 kHz 16-bit mono PCM file.")
        }
        let audio = try Data(contentsOf: URL(fileURLWithPath: path))

        let session = try await client.transcribeRealtime(
            speechModel: BitmeshRealtimeSpeechModel.universalStreamingEnglish,
            formatTurns: true
        )
        XCTAssertFalse(session.begin.id.isEmpty)

        let reader = Task { () -> [String] in
            var turns: [String] = []
            for try await event in session.events {
                if case .turn(let turn) = event, turn.endOfTurn { turns.append(turn.transcript) }
            }
            return turns
        }

        var offset = 0
        while offset < audio.count {
            try await session.sendAudio(audio.subdata(in: offset..<min(offset + 1600, audio.count)))
            offset += 1600
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let end = await session.terminate()
        let turns = try await reader.value

        print("Transcript: \(turns.joined(separator: " "))")
        XCTAssertFalse(turns.joined().isEmpty)
        XCTAssertEqual(session.closeCode, 1000)
        XCTAssertEqual(end?.audioDurationSeconds ?? 0, Double(audio.count) / 32000, accuracy: 1.5)
        XCTAssertGreaterThan(end?.sessionDurationSeconds ?? 0, 0)
    }

    func testRealtimeRefusesAWrongKey() async throws {
        try Self.requireWebSockets()
        _ = try BitmeshTestSupport.makeClient()
        let client = BitmeshClient(apiKey: "bmk_not_a_key", baseURL: BitmeshTestSupport.baseURL)
        do {
            _ = try await client.transcribeRealtime()
            XCTFail("Expected 401")
        } catch let error as BitmeshError {
            XCTAssertEqual(error.statusCode, 401)
        }
    }
}
