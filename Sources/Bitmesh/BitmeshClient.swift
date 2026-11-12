import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Returns a current Firebase App Check token, or `nil` if none is available.
///
/// Called before every request. Return the Firebase SDK's cached token; it
/// refreshes itself:
///
/// ```swift
/// appCheckTokenProvider: { try await AppCheck.appCheck().token(forcingRefresh: false).token }
/// ```
public typealias BitmeshAppCheckTokenProvider = @Sendable () async throws -> String?

/// Client for the Bitmesh AI API v2: chat (streaming included), image, video,
/// transcription, tools and the provider proxy.
///
/// Every request carries the key as `Authorization: Bearer`, plus the App Check
/// token (or a debug token) on mobile keys.
public final class BitmeshClient: @unchecked Sendable {
    public static let defaultBaseURL = "https://api.bitmesh.ai"

    /// The API version every authenticated path is served under.
    public static let apiVersion = "v2"

    /// Header carrying the Firebase App Check token on mobile keys.
    public static let appCheckHeader = "X-Firebase-AppCheck"

    /// Header carrying a debug token in place of App Check while testing.
    public static let debugTokenHeader = "X-Bitmesh-Debug-Token"

    private let apiKey: String
    private let baseURL: String
    let timeoutSeconds: TimeInterval
    let session: URLSession
    private let appCheckTokenProvider: BitmeshAppCheckTokenProvider?
    private let debugToken: String?

    /// Creates a client for a v2 key.
    /// - Parameters:
    ///   - apiKey: A v2 key from the dashboard, starting `bmk_` (hosted or proxy).
    ///   - timeoutSeconds: Request timeout (default 30). For a streamed reply,
    ///     the longest wait for the next piece.
    ///   - baseURL: API host without a version (default `https://api.bitmesh.ai`).
    ///   - session: `URLSession` used for HTTP (default `.shared`).
    ///   - appCheckTokenProvider: Supplies the Firebase App Check token sent as
    ///     `X-Firebase-AppCheck`. Required when the key is a mobile key: the API
    ///     refuses every request on one without a valid token. Leave `nil` for
    ///     server keys.
    ///   - debugToken: A Bitmesh debug token (`bmdbg_...`) sent as
    ///     `X-Bitmesh-Debug-Token` in place of App Check, for simulators. When set,
    ///     `appCheckTokenProvider` is not called. Never set it in a release build.
    public init(
        apiKey: String,
        timeoutSeconds: TimeInterval = 30,
        baseURL: String = BitmeshClient.defaultBaseURL,
        session: URLSession = .shared,
        appCheckTokenProvider: BitmeshAppCheckTokenProvider? = nil,
        debugToken: String? = nil
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.timeoutSeconds = timeoutSeconds
        self.session = session
        self.appCheckTokenProvider = appCheckTokenProvider
        self.debugToken = debugToken
    }

    // MARK: - Account

    /// `GET /v2/balance`: the account's credit balance.
    public func balance() async throws -> Double {
        let json = try await getJSON(path: "/balance")
        if let number = json["balance"] as? NSNumber { return number.doubleValue }
        return Double(json["balance"] as? String ?? "") ?? 0
    }

    /// `GET /v2/test`: returns when the key (and, on a mobile key, the App Check
    /// or debug token) is accepted. Throws otherwise.
    public func verify() async throws {
        _ = try await getJSON(path: "/test")
    }

    // MARK: - Chat / Image / Video

    /// `POST /v2/chat` with a JSON payload (e.g. `model`, `messages`, `max_tokens`).
    public func chat(payload: BitmeshJSON) async throws -> BitmeshJSON {
        try await postJSON(path: "/chat", payload: payload)
    }

    /// `POST /v2/chat` with `"stream": true`: yields each chunk of the reply as
    /// it is written, in OpenAI's format. The new text is in
    /// `choices[0].delta.content`; the last chunk carries `usage`.
    ///
    /// The request is billed once, when the stream ends. Stop iterating (or
    /// cancel the task) to stop generating: you pay only for what was written.
    public func chatStream(payload: BitmeshJSON) -> AsyncThrowingStream<BitmeshJSON, Error> {
        var body = payload
        body["stream"] = true
        let events = eventStream(method: "POST", path: "/chat", payload: body)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in events {
                        if event.isDone { break }
                        let json = try event.json()
                        if json["error"] != nil {
                            // The provider failed after the reply had started.
                            throw BitmeshError.httpError(statusCode: 502, body: event.data)
                        }
                        continuation.yield(json)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `POST /v2/image` with a JSON payload.
    public func image(payload: BitmeshJSON) async throws -> BitmeshJSON {
        try await postJSON(path: "/image", payload: payload)
    }

    /// `POST /v2/video` with a JSON payload.
    public func video(payload: BitmeshJSON) async throws -> BitmeshJSON {
        try await postJSON(path: "/video", payload: payload)
    }

    /// `GET /v2/video/{id}`: poll video job status or result.
    public func getVideo(id: String, query: [String: String] = [:]) async throws -> BitmeshJSON {
        let id = try pathSegment(id, error: "Video job id is required.")
        return try await getJSON(path: "/video/\(id)", query: query)
    }

    // MARK: - Transcription

    /// `POST /v2/transcribe-recorded`: upload audio as multipart field `audio`.
    public func transcribeFile(audioFileURL: URL, fields: BitmeshJSON = [:]) async throws -> BitmeshJSON {
        let audioData = try FileValidator.validateReadableFile(at: audioFileURL, field: "audio")
        return try await postMultipart(
            path: "/transcribe-recorded",
            fields: fields,
            files: [("audio", audioFileURL.lastPathComponent, FileValidator.mimeType(for: audioFileURL), audioData)]
        )
    }

    /// `GET /v2/transcribe-recorded/{id}`: poll a transcription job.
    public func getTranscribeRecorded(id: String, query: [String: String] = [:]) async throws -> BitmeshJSON {
        let id = try pathSegment(id, error: "Transcription job id is required.")
        return try await getJSON(path: "/transcribe-recorded/\(id)", query: query)
    }

    // MARK: - Tools

    /// `POST /v2/tools/general/background-removal`
    public func toolsGeneralBackgroundRemoval(fields: BitmeshJSON, imageFileURL: URL) async throws -> BitmeshJSON {
        let imageData = try FileValidator.validateReadableFile(at: imageFileURL, field: "image")
        return try await postMultipart(
            path: "/tools/general/background-removal",
            fields: fields,
            files: [("image", imageFileURL.lastPathComponent, FileValidator.mimeType(for: imageFileURL), imageData)]
        )
    }

    /// `POST /v2/tools/portrait/try-on-clothes`
    public func toolsPortraitTryOnClothes(fields: BitmeshJSON, files: [String: URL]) async throws -> BitmeshJSON {
        var fileParts: [(String, String, String, Data)] = []
        for (fieldName, url) in files.sorted(by: { $0.key < $1.key }) {
            let data = try FileValidator.validateReadableFile(at: url, field: fieldName)
            fileParts.append((fieldName, url.lastPathComponent, FileValidator.mimeType(for: url), data))
        }
        return try await postMultipart(
            path: "/tools/portrait/try-on-clothes",
            fields: fields,
            files: fileParts
        )
    }

    /// `POST /v2/tools/query-async-task-result`
    public func toolsQueryAsyncTaskResult(taskId: String) async throws -> BitmeshJSON {
        let trimmed = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BitmeshError.validation("Task id is required.")
        }
        return try await postJSON(path: "/tools/query-async-task-result", payload: ["task_id": trimmed])
    }

    /// `POST /v2/tools/video/image-animate`: image-to-video. Async: returns
    /// `data.task_id` straight away; poll with `getImageAnimate(taskId:)`.
    ///
    /// Payload keys: `model` (`animate-2.4-faster` or `animate-2.4-advanced`),
    /// `image` (`["bytes_base64_encoded": data.base64EncodedString()]`),
    /// `seconds` (1–10), and optional `prompt`, `aspect_ratio`, `callback_url`, `test`.
    public func imageAnimate(payload: BitmeshJSON) async throws -> BitmeshJSON {
        try await postJSON(path: "/tools/video/image-animate", payload: payload)
    }

    /// `GET /v2/tools/video/image-animate/{task_id}`: poll an image-to-video task.
    /// `data.status` ends at `SUCCESS`, `FAILED` or `CANCELED`; on success the
    /// video links are in `data.output_videos[].url`. Pass `["test": "1"]` as
    /// `query` for a task created in test mode.
    public func getImageAnimate(taskId: String, query: [String: String] = [:]) async throws -> BitmeshJSON {
        let id = try pathSegment(taskId, error: "Image-animate task id is required.")
        return try await getJSON(path: "/tools/video/image-animate/\(id)", query: query)
    }

    /// `GET /tools-result/{path}`: a tool's result file. Public, so no key is sent.
    public func getToolsResult(path: String) async throws -> Data {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            throw BitmeshError.validation("Tools result path is required.")
        }
        var request = URLRequest(url: try url(for: "/tools-result/\(trimmed)", versioned: false))
        request.timeoutInterval = timeoutSeconds
        return try await perform(request).data
    }

    // MARK: - Proxy

    /// A request through the provider proxy, `/v2/proxy/{provider}/{path}`, with
    /// a proxy key. Send the provider's own request minus its API key header;
    /// Bitmesh adds the stored provider key. `headers` passes provider headers
    /// that select options, such as `anthropic-version`.
    ///
    /// Returns the provider's JSON reply. A non-2xx answer throws
    /// `BitmeshError.httpError` with the body, from Bitmesh or the provider.
    public func proxy(
        provider: String,
        path: String,
        method: String = "POST",
        payload: BitmeshJSON? = nil,
        headers: [String: String] = [:]
    ) async throws -> BitmeshJSON {
        let request = try await makeRequest(
            method: method,
            path: try proxyPath(provider: provider, path: path),
            payload: payload,
            headers: headers
        )
        return try JSONHelpers.decodeJSONObject(from: try await perform(request).data)
    }

    /// A streamed request through the provider proxy: sends `"stream": true` and
    /// yields the provider's server-sent events as they arrive. OpenAI-style
    /// streams end with an event whose `isDone` is true; Anthropic names each
    /// event in `event`.
    public func proxyStream(
        provider: String,
        path: String,
        payload: BitmeshJSON,
        headers: [String: String] = [:]
    ) -> AsyncThrowingStream<ServerSentEvent, Error> {
        var body = payload
        body["stream"] = true
        do {
            return eventStream(
                method: "POST",
                path: try proxyPath(provider: provider, path: path),
                payload: body,
                headers: headers
            )
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    // MARK: - HTTP

    private func postJSON(path: String, payload: BitmeshJSON) async throws -> BitmeshJSON {
        let request = try await makeRequest(method: "POST", path: path, payload: payload)
        return try JSONHelpers.decodeJSONObject(from: try await perform(request).data)
    }

    private func getJSON(path: String, query: [String: String] = [:]) async throws -> BitmeshJSON {
        let request = try await makeRequest(method: "GET", path: path, query: query)
        return try JSONHelpers.decodeJSONObject(from: try await perform(request).data)
    }

    private func postMultipart(
        path: String,
        fields: BitmeshJSON,
        files: [(name: String, filename: String, mimeType: String, data: Data)]
    ) async throws -> BitmeshJSON {
        var form = MultipartFormData()
        for field in MultipartFieldFlattener.flatten(MultipartFieldFlattener.wireFields(fields)) {
            form.addField(name: field.name, value: field.value)
        }
        for file in files {
            form.addFile(name: file.name, filename: file.filename, mimeType: file.mimeType, data: file.data)
        }

        var request = try await makeRequest(method: "POST", path: path)
        request.httpBody = form.finalize()
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        return try JSONHelpers.decodeJSONObject(from: try await perform(request).data)
    }

    /// An authenticated request to `{baseURL}/v2/{path}`. Per-call `headers` go
    /// first, so they can't replace the key or the App Check token.
    func makeRequest(
        method: String,
        path: String,
        query: [String: String] = [:],
        payload: BitmeshJSON? = nil,
        headers: [String: String] = [:]
    ) async throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw BitmeshError.validation("The Bitmesh API key is empty.")
        }
        guard apiKey.hasPrefix("bmk_") else {
            throw BitmeshError.validation(
                "Bitmesh API v2 keys start with \"bmk_\". A v1 consumer key and secret is not supported by this SDK; create a v2 key in the dashboard."
            )
        }

        var request = URLRequest(url: try url(for: path, query: query, versioned: true))
        request.httpMethod = method
        request.timeoutInterval = timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            request.httpBody = Data(try JSONHelpers.encodeJSONObject(payload).utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let debugToken {
            request.setValue(debugToken, forHTTPHeaderField: Self.debugTokenHeader)
        } else if let appCheckToken = try await fetchAppCheckToken() {
            request.setValue(appCheckToken, forHTTPHeaderField: Self.appCheckHeader)
        }
        return request
    }

    /// The App Check token for one request, or `nil` when no provider is set.
    ///
    /// A provider that fails stops the request here: without a token a mobile
    /// key is refused anyway, so there is no point sending it.
    private func fetchAppCheckToken() async throws -> String? {
        guard let appCheckTokenProvider else { return nil }

        let token: String?
        do {
            token = try await appCheckTokenProvider()
        } catch {
            throw BitmeshAppCheckTokenError(underlying: error)
        }

        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BitmeshAppCheckTokenError(underlying: nil)
        }
        return token
    }

    private func perform(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            #if canImport(FoundationNetworking)
            (data, response) = try await session.linuxData(for: request)
            #else
            (data, response) = try await session.data(for: request)
            #endif
        } catch {
            throw BitmeshError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BitmeshError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw BitmeshError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        return (data, httpResponse)
    }

    /// Server-sent events from an authenticated request. Errors before the
    /// stream starts come back as JSON with their status code and are thrown.
    private func eventStream(
        method: String,
        path: String,
        payload: BitmeshJSON,
        headers: [String: String] = [:]
    ) -> AsyncThrowingStream<ServerSentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try await makeRequest(
                        method: method,
                        path: path,
                        payload: payload,
                        headers: headers
                    )
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    var parser = ServerSentEventParser()
                    #if canImport(FoundationNetworking)
                    // swift-corelibs-foundation has no URLSession.bytes: read the whole body.
                    let (data, _) = try await perform(request)
                    for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
                        if let event = parser.feed(String(line)) { continuation.yield(event) }
                    }
                    #else
                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await session.bytes(for: request)
                    } catch {
                        throw BitmeshError.networkError(error)
                    }
                    guard let http = response as? HTTPURLResponse else {
                        throw BitmeshError.invalidResponse
                    }
                    guard (200...299).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        throw BitmeshError.httpError(statusCode: http.statusCode, body: String(data: body, encoding: .utf8))
                    }
                    // Split lines ourselves: AsyncBytes.lines drops the blank
                    // lines that end each event.
                    var line = Data()
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            if let event = parser.feed(String(decoding: line, as: UTF8.self)) {
                                continuation.yield(event)
                            }
                            line.removeAll(keepingCapacity: true)
                        } else {
                            line.append(byte)
                        }
                    }
                    if !line.isEmpty, let event = parser.feed(String(decoding: line, as: UTF8.self)) {
                        continuation.yield(event)
                    }
                    #endif
                    if let event = parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func proxyPath(provider: String, path: String) throws -> String {
        let name = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard name.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else {
            throw BitmeshError.validation("Invalid provider \"\(provider)\". Use the provider's name as in the docs, e.g. \"openai\", \"anthropic\" or \"together\".")
        }
        return "/proxy/\(name)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))"
    }

    private func pathSegment(_ id: String, error: String) throws -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BitmeshError.validation(error)
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    private func url(for path: String, query: [String: String] = [:], versioned: Bool) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = versioned ? "\(Self.apiVersion)/" : ""
        guard var components = URLComponents(string: "\(baseURL)/\(prefix)\(trimmedPath)"),
              components.scheme != nil, components.host != nil
        else {
            throw BitmeshError.validation("Invalid baseURL \"\(baseURL)\". Expected an absolute URL such as \"https://api.bitmesh.ai\".")
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
                .sorted(by: { $0.key < $1.key })
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw BitmeshError.validation("Invalid request path \"\(path)\".")
        }
        return url
    }
}

#if canImport(FoundationNetworking)
extension URLSession {
    /// swift-corelibs-foundation (Linux) has no async `data(for:)`.
    fileprivate func linuxData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let response {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }.resume()
        }
    }
}
#endif
