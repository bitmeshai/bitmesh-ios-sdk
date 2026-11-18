import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The real-time transcription models, for `transcribeRealtime(speechModel:)`.
public enum BitmeshRealtimeSpeechModel {
    /// The default: 32 languages, switching mid-sentence, punctuated and cased.
    public static let universal36Pro = "universal-3-6-pro"

    /// English only. Lowercase without punctuation unless `formatTurns` is set.
    public static let universalStreamingEnglish = "universal-streaming-english"

    /// English, Spanish, German, French, Portuguese and Italian, one per turn.
    public static let universalStreamingMultilingual = "universal-streaming-multilingual"
}

/// The session started.
public struct RealtimeBegin: @unchecked Sendable {
    /// The session id.
    public let id: String
    /// The latest time the session may run to: an hour, or less when the
    /// balance covers less.
    public let expiresAt: Date?
    /// The message as received.
    public let raw: BitmeshJSON

    public init(json: BitmeshJSON) {
        id = json["id"] as? String ?? ""
        expiresAt = RealtimeJSON.double(json["expires_at"]).map { Date(timeIntervalSince1970: $0) }
        raw = json
    }
}

/// The transcript of one turn so far. The same turn is sent again each time it
/// changes; it is final when `endOfTurn` is true, so keep the last one of each
/// `turnOrder`.
public struct RealtimeTurn: @unchecked Sendable {
    /// Counts the turns of the session from 0.
    public let turnOrder: Int
    /// The words of the turn so far.
    public let transcript: String
    /// True when the turn is finished and `transcript` won't change again.
    public let endOfTurn: Bool
    /// True when `transcript` is punctuated and cased.
    public let isFormatted: Bool
    /// The turn's language, with `languageDetection: true`.
    public let languageCode: String?
    /// How sure the model is of `languageCode`, from 0 to 1.
    public let languageConfidence: Double?
    /// Word-level detail (`text`, `start`, `end`, `confidence`), as received.
    public let words: [BitmeshJSON]
    /// The message as received.
    public let raw: BitmeshJSON

    public init(json: BitmeshJSON) {
        turnOrder = Int(RealtimeJSON.double(json["turn_order"]) ?? 0)
        transcript = json["transcript"] as? String ?? ""
        endOfTurn = json["end_of_turn"] as? Bool ?? false
        isFormatted = json["turn_is_formatted"] as? Bool ?? false
        languageCode = json["language_code"] as? String
        languageConfidence = RealtimeJSON.double(json["language_confidence"])
        words = json["words"] as? [BitmeshJSON] ?? []
        raw = json
    }
}

/// The session ended. `sessionDurationSeconds` is the time billed.
public struct RealtimeTermination: @unchecked Sendable {
    /// Seconds of audio the session received.
    public let audioDurationSeconds: Double?
    /// Seconds the session was open: the time it is billed for.
    public let sessionDurationSeconds: Double?
    /// The message as received.
    public let raw: BitmeshJSON

    public init(json: BitmeshJSON) {
        audioDurationSeconds = RealtimeJSON.double(json["audio_duration_seconds"])
        sessionDurationSeconds = RealtimeJSON.double(json["session_duration_seconds"])
        raw = json
    }
}

/// A message from a real-time transcription session: one `begin`, a `turn`
/// each time the transcript changes, and `termination` last. Message types
/// this SDK doesn't know come as `other`.
public enum RealtimeTranscriptionEvent: @unchecked Sendable {
    case begin(RealtimeBegin)
    case turn(RealtimeTurn)
    case termination(RealtimeTermination)
    case other(type: String, raw: BitmeshJSON)

    public init(json: BitmeshJSON) {
        switch json["type"] as? String {
        case "Begin": self = .begin(RealtimeBegin(json: json))
        case "Turn": self = .turn(RealtimeTurn(json: json))
        case "Termination": self = .termination(RealtimeTermination(json: json))
        default: self = .other(type: json["type"] as? String ?? "", raw: json)
        }
    }

    /// The message as received.
    public var raw: BitmeshJSON {
        switch self {
        case .begin(let begin): return begin.raw
        case .turn(let turn): return turn.raw
        case .termination(let termination): return termination.raw
        case .other(_, let raw): return raw
        }
    }
}

/// A real-time transcription session closed other than normally (close code
/// 1000). It ends the session's `events`, after any `termination`.
///
/// `3008`: the session reached its time limit (an hour, or less when the
/// balance covers less). `1001`: the server restarted; reconnect, the session
/// is billed for the time it ran. `1011`: the transcription service failed.
/// Other codes from 3000 to 4999 come from the transcription service, with the
/// reason in `reason`. `1006`: the connection was lost.
public struct BitmeshRealtimeClosedError: Error, LocalizedError, Sendable {
    /// The WebSocket close code.
    public let code: Int
    /// The close reason.
    public let reason: String

    /// True for 3008, a session that reached its time limit.
    public var isTimeLimit: Bool { code == 3008 }

    public var errorDescription: String? { "Real-time transcription closed with code \(code): \(reason)" }
}

/// An open real-time transcription session, from
/// `BitmeshClient.transcribeRealtime`.
///
/// Send audio with `sendAudio(_:)` as it is recorded, read the transcript from
/// `events`, and call `terminate()` when you are done:
///
/// ```swift
/// let session = try await client.transcribeRealtime(sampleRate: 16000)
/// Task {
///     for try await event in session.events {
///         if case .turn(let turn) = event, turn.endOfTurn { print(turn.transcript) }
///     }
/// }
/// try await session.sendAudio(pcmChunk) // 16-bit mono PCM, about 50 ms at a time
/// let end = await session.terminate()
/// ```
///
/// The session is billed for the time it is open, silence included, so end it
/// as soon as you are done.
public final class BitmeshRealtimeTranscription: @unchecked Sendable {
    /// The session's `Begin` message.
    public let begin: RealtimeBegin

    /// Every message of the session, in order, from `begin` to `termination`.
    /// Messages are kept until you read them. It ends when the session closes,
    /// throwing `BitmeshRealtimeClosedError` for a close other than a normal one.
    public let events: AsyncThrowingStream<RealtimeTranscriptionEvent, Error>

    private let task: URLSessionWebSocketTask
    private let continuation: AsyncThrowingStream<RealtimeTranscriptionEvent, Error>.Continuation
    private let lock = NSLock()
    private var termination: RealtimeTermination?
    private var ending = false
    private var closedByClient = false
    private var finishedCode: Int?
    private var waiters: [CheckedContinuation<RealtimeTermination?, Never>] = []

    init(task: URLSessionWebSocketTask, begin: RealtimeBegin) {
        self.task = task
        self.begin = begin
        (events, continuation) = AsyncThrowingStream.makeStream(of: RealtimeTranscriptionEvent.self)
        continuation.yield(.begin(begin))
        Task { await self.receiveLoop() }
    }

    /// True once the connection has closed.
    public var isClosed: Bool { withLock { finishedCode != nil } }

    /// The close code once closed: 1000 for a normal end.
    public var closeCode: Int? { withLock { finishedCode } }

    /// Sends a piece of audio: raw 16-bit little-endian mono PCM at the session's
    /// sample rate (or μ-law with `encoding: "pcm_mulaw"`). Send it as it is
    /// recorded, about 50 ms at a time: 1,600 bytes at 16 kHz.
    public func sendAudio(_ audio: Data) async throws {
        try checkOpen()
        do {
            try await task.send(.data(audio))
        } catch {
            throw BitmeshError.networkError(error)
        }
    }

    /// Ends the current turn now, without waiting for a pause.
    public func forceEndpoint() async throws {
        try await send(message: ["type": "ForceEndpoint"])
    }

    /// Sends a JSON control message, such as `["type": "UpdateConfiguration", ...]`.
    public func send(message: BitmeshJSON) async throws {
        try checkOpen()
        let text = try JSONHelpers.encodeJSONObject(message)
        do {
            try await task.send(.string(text))
        } catch {
            throw BitmeshError.networkError(error)
        }
    }

    /// Ends the session: turns still in progress arrive, then `termination`,
    /// then the connection closes. Returns the `Termination` message, or `nil`
    /// when the session closed without one.
    ///
    /// Closes the connection itself if the server hasn't within `timeoutSeconds`.
    @discardableResult
    public func terminate(timeoutSeconds: TimeInterval = 30) async -> RealtimeTermination? {
        let shouldSend = withLock { () -> Bool in
            defer { ending = true }
            return !ending && finishedCode == nil
        }
        if shouldSend {
            try? await task.send(.string(#"{"type":"Terminate"}"#))
        }
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(timeoutSeconds, 0) * 1_000_000_000))
            if !Task.isCancelled { self?.close() }
        }
        let result = await waitForEnd()
        timer.cancel()
        return result
    }

    /// Closes the connection straight away. Prefer `terminate()`, which lets the
    /// last turn arrive. The session is billed up to the close either way.
    public func close() {
        withLock {
            ending = true
            closedByClient = true
        }
        task.cancel(with: .normalClosure, reason: nil)
    }

    private func receiveLoop() async {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                finish()
                return
            }
            guard case .string(let text) = message,
                  let json = try? JSONHelpers.decodeJSONObject(from: Data(text.utf8))
            else { continue }
            let event = RealtimeTranscriptionEvent(json: json)
            if case .termination(let end) = event {
                withLock { termination = end }
            }
            continuation.yield(event)
        }
    }

    private func finish() {
        let reported = task.closeCode.rawValue
        let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let (code, end, pending) = withLock { () -> (Int, RealtimeTermination?, [CheckedContinuation<RealtimeTermination?, Never>]) in
            // A close we started, or the server's normal close after Terminate.
            let code = closedByClient || reported == 1000 ? 1000 : (reported == 0 ? 1006 : reported)
            finishedCode = code
            defer { waiters.removeAll() }
            return (code, termination, waiters)
        }
        if code == 1000 {
            continuation.finish()
        } else {
            continuation.finish(throwing: BitmeshRealtimeClosedError(
                code: code,
                reason: reason.isEmpty ? (code == 1006 ? "The connection was lost." : "The session closed with code \(code).") : reason
            ))
        }
        pending.forEach { $0.resume(returning: end) }
    }

    private func waitForEnd() async -> RealtimeTermination? {
        await withCheckedContinuation { waiter in
            lock.lock()
            if finishedCode != nil {
                let end = termination
                lock.unlock()
                waiter.resume(returning: end)
            } else {
                waiters.append(waiter)
                lock.unlock()
            }
        }
    }

    private func checkOpen() throws {
        if withLock({ ending || finishedCode != nil }) {
            throw BitmeshError.validation("The real-time transcription session has ended.")
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

extension BitmeshClient {
    /// Opens a real-time transcription session: a WebSocket to
    /// `/v2/transcribe-realtime`. Send audio as it is recorded and the
    /// transcript comes back turn by turn; see `BitmeshRealtimeTranscription`.
    ///
    /// - Parameters:
    ///   - sampleRate: Sample rate of the audio you will send, in Hz.
    ///   - speechModel: One of `BitmeshRealtimeSpeechModel` (default `universal-3-6-pro`).
    ///   - encoding: `pcm_s16le` (default) or `pcm_mulaw`.
    ///   - formatTurns: Punctuate and case final turns of the `universal-streaming-*` models.
    ///   - languageDetection: Add the language to each turn.
    ///   - query: Further connection settings of the transcription service.
    ///
    /// Returns once the session has begun. A refused connection throws
    /// `BitmeshError.httpError` before any audio is sent: 401 (key or App
    /// Check), 402 (less than a minute's balance), 403, 422 (settings), 429 (too
    /// many sessions open on the key) or 502. Its body isn't available on a
    /// WebSocket, so `apiMessage` is `nil`. Apple platforms only: on Linux it
    /// throws `BitmeshError.validation`.
    public func transcribeRealtime(
        sampleRate: Int = 16000,
        speechModel: String? = nil,
        encoding: String? = nil,
        formatTurns: Bool? = nil,
        languageDetection: Bool? = nil,
        query: [String: String] = [:]
    ) async throws -> BitmeshRealtimeTranscription {
        guard sampleRate > 0 else {
            throw BitmeshError.validation("sampleRate must be positive.")
        }
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation's URLSession can't open WebSockets.
        throw BitmeshError.validation("Real-time transcription needs URLSessionWebSocketTask, available on Apple platforms only.")
        #else
        var settings = query
        settings["sample_rate"] = String(sampleRate)
        if let speechModel { settings["speech_model"] = speechModel }
        if let encoding { settings["encoding"] = encoding }
        if let formatTurns { settings["format_turns"] = formatTurns ? "true" : "false" }
        if let languageDetection { settings["language_detection"] = languageDetection ? "true" : "false" }

        var request = try await makeRequest(method: "GET", path: "/transcribe-realtime", query: settings)
        request.url = try Self.webSocketURL(request.url)
        // The connection stays open for the whole session; the handshake has
        // its own timeout below.
        request.timeoutInterval = 3_700

        let task = session.webSocketTask(with: request)
        let handshakeTimeout = timeoutSeconds
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(handshakeTimeout, 1) * 1_000_000_000))
            if !Task.isCancelled { task.cancel(with: .goingAway, reason: nil) }
        }
        defer { timer.cancel() }
        task.resume()

        // The server's first message is Begin. A refused handshake makes
        // receive() throw, with the HTTP status on the task's response.
        let first: URLSessionWebSocketTask.Message
        do {
            first = try await task.receive()
        } catch {
            let status = (task.response as? HTTPURLResponse)?.statusCode
            task.cancel(with: .goingAway, reason: nil)
            if let status, status != 101 {
                throw BitmeshError.httpError(statusCode: status, body: nil)
            }
            throw BitmeshError.networkError(error)
        }
        timer.cancel()

        guard case .string(let text) = first,
              let json = try? JSONHelpers.decodeJSONObject(from: Data(text.utf8)),
              case .begin(let begin) = RealtimeTranscriptionEvent(json: json)
        else {
            task.cancel(with: .protocolError, reason: nil)
            throw BitmeshError.invalidResponse
        }
        return BitmeshRealtimeTranscription(task: task, begin: begin)
        #endif
    }

    /// `https://` becomes `wss://` and `http://` becomes `ws://`.
    static func webSocketURL(_ url: URL?) throws -> URL {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BitmeshError.validation("Invalid real-time transcription URL.")
        }
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        guard let result = components.url else {
            throw BitmeshError.validation("Invalid real-time transcription URL.")
        }
        return result
    }
}

enum RealtimeJSON {
    static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
