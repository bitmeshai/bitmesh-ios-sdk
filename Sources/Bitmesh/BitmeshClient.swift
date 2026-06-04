import Foundation

/// Client for the Bitmesh AI API (chat, image, video, transcription, and tools).
///
/// All signed requests use OAuth 1.0 and `X-Payload-Signature` matching the PHP SDK.
public final class BitmeshClient: @unchecked Sendable {
    public static let defaultBaseURL = "https://api.bitmesh.ai"

    private let key: String
    private let secret: String
    private let baseURL: URL
    private let timeoutSeconds: TimeInterval
    private let session: URLSession

    /// Creates a client with OAuth credentials.
    /// - Parameters:
    ///   - key: OAuth consumer key
    ///   - secret: OAuth consumer secret
    ///   - timeoutSeconds: Request timeout (default 30)
    ///   - baseURL: API host (default `https://api.bitmesh.ai`)
    ///   - session: `URLSession` used for HTTP (default `.shared`)
    public init(
        key: String,
        secret: String,
        timeoutSeconds: TimeInterval = 30,
        baseURL: String = BitmeshClient.defaultBaseURL,
        session: URLSession = .shared
    ) {
        self.key = key
        self.secret = secret
        self.baseURL = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
        self.timeoutSeconds = timeoutSeconds
        self.session = session
    }

    // MARK: - Chat / Image / Video

    /// `POST /chat` with a JSON payload (e.g. `model`, `messages`, `max_tokens`).
    public func chat(payload: BitmeshJSON) async throws -> BitmeshJSON {
        try await sendSignedJSONRequest(method: "POST", path: "/chat", payload: payload)
    }

    /// `POST /image` with a JSON payload.
    public func image(payload: BitmeshJSON) async throws -> BitmeshJSON {
        try await sendSignedJSONRequest(method: "POST", path: "/image", payload: payload)
    }

    /// `POST /video` with a JSON payload.
    public func video(payload: BitmeshJSON) async throws -> BitmeshJSON {
        try await sendSignedJSONRequest(method: "POST", path: "/video", payload: payload)
    }

    /// `GET /video/{id}` — poll video job status or result.
    public func getVideo(id: String, query: [String: String] = [:]) async throws -> BitmeshJSON {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BitmeshError.validation("Video job id is required.")
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return try await sendSignedGETRequest(path: "/video/\(encoded)", query: query)
    }

    // MARK: - Transcription

    /// `POST /transcribe-recorded` — upload audio as multipart field `audio`.
    public func transcribeFile(audioFileURL: URL, fields: BitmeshJSON = [:]) async throws -> BitmeshJSON {
        let audioData = try FileValidator.validateReadableFile(at: audioFileURL, field: "audio")
        return try await sendSignedMultipartRequest(
            path: "/transcribe-recorded",
            fields: fields,
            files: [("audio", audioFileURL.lastPathComponent, FileValidator.mimeType(for: audioFileURL), audioData)]
        )
    }

    /// `GET /transcribe-recorded/{id}` — poll transcription job.
    public func getTranscribeRecorded(id: String, query: [String: String] = [:]) async throws -> BitmeshJSON {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BitmeshError.validation("Transcription job id is required.")
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return try await sendSignedGETRequest(path: "/transcribe-recorded/\(encoded)", query: query)
    }

    // MARK: - Tools

    /// `POST /tools/general/background-removal`
    public func toolsGeneralBackgroundRemoval(fields: BitmeshJSON, imageFileURL: URL) async throws -> BitmeshJSON {
        let imageData = try FileValidator.validateReadableFile(at: imageFileURL, field: "image")
        return try await sendSignedMultipartRequest(
            path: "/tools/general/background-removal",
            fields: fields,
            files: [("image", imageFileURL.lastPathComponent, FileValidator.mimeType(for: imageFileURL), imageData)]
        )
    }

    /// `POST /tools/portrait/try-on-clothes`
    public func toolsPortraitTryOnClothes(fields: BitmeshJSON, files: [String: URL]) async throws -> BitmeshJSON {
        var fileParts: [(String, String, String, Data)] = []
        for (fieldName, url) in files {
            let data = try FileValidator.validateReadableFile(at: url, field: fieldName)
            fileParts.append((fieldName, url.lastPathComponent, FileValidator.mimeType(for: url), data))
        }
        return try await sendSignedMultipartRequest(
            path: "/tools/portrait/try-on-clothes",
            fields: fields,
            files: fileParts
        )
    }

    /// `POST /tools/query-async-task-result`
    public func toolsQueryAsyncTaskResult(taskId: String) async throws -> BitmeshJSON {
        let trimmed = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BitmeshError.validation("Task id is required.")
        }
        return try await sendSignedJSONRequest(
            method: "POST",
            path: "/tools/query-async-task-result",
            payload: ["task_id": trimmed]
        )
    }

    /// `GET /tools-result/{path}` — unsigned proxied asset fetch.
    public func getToolsResult(path: String) async throws -> Data {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            throw BitmeshError.validation("Tools result path is required.")
        }
        return try await sendUnsignedGETRequest(path: "/tools-result/\(trimmed)")
    }

    // MARK: - HTTP

    private func sendSignedJSONRequest(method: String, path: String, payload: BitmeshJSON) async throws -> BitmeshJSON {
        let url = buildURL(path: path)
        let jsonBody = try JSONHelpers.encodeJSONObject(payload)
        let bodyData = Data(jsonBody.utf8)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.timeoutInterval = timeoutSeconds
        try applySignedHeaders(to: &request, method: method, url: url.absoluteString, body: jsonBody, multipartFields: nil)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await performRequest(request)
        return try JSONHelpers.decodeJSONObject(from: data)
    }

    private func sendSignedGETRequest(path: String, query: [String: String]) async throws -> BitmeshJSON {
        let url = buildURL(path: path, query: query)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        try applySignedHeaders(to: &request, method: "GET", url: url.absoluteString, body: "", multipartFields: nil)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await performRequest(request)
        return try JSONHelpers.decodeJSONObject(from: data)
    }

    private func sendUnsignedGETRequest(path: String) async throws -> Data {
        let url = buildURL(path: path)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds

        return try await performRequest(request)
    }

    private func sendSignedMultipartRequest(
        path: String,
        fields: BitmeshJSON,
        files: [(name: String, filename: String, mimeType: String, data: Data)]
    ) async throws -> BitmeshJSON {
        let url = buildURL(path: path)
        var form = MultipartFormData()
        let flattened = MultipartFieldFlattener.flatten(fields)
        for (name, value) in flattened.sorted(by: { $0.key < $1.key }) {
            form.addField(name: name, value: value)
        }
        for file in files {
            form.addFile(name: file.name, filename: file.filename, mimeType: file.mimeType, data: file.data)
        }
        let bodyData = form.finalize()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = timeoutSeconds
        try applySignedHeaders(to: &request, method: "POST", url: url.absoluteString, body: nil, multipartFields: fields)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await performRequest(request)
        return try JSONHelpers.decodeJSONObject(from: data)
    }

    private func applySignedHeaders(
        to request: inout URLRequest,
        method: String,
        url: String,
        body: String?,
        multipartFields: BitmeshJSON?
    ) throws {
        let oauthParams = OAuthHelper.generateOAuthParams(
            method: method,
            url: url,
            consumerKey: key,
            consumerSecret: secret
        )
        let oauthSignature = oauthParams["oauth_signature"] ?? ""

        let payloadSignature: String
        if let multipartFields {
            payloadSignature = try OAuthHelper.multipartPayloadSignature(
                fields: multipartFields,
                consumerKey: key,
                oauthSignature: oauthSignature
            )
        } else {
            payloadSignature = OAuthHelper.payloadSignature(
                body: body ?? "",
                consumerKey: key,
                oauthSignature: oauthSignature
            )
        }

        request.setValue(OAuthHelper.buildAuthorizationHeader(oauthParams: oauthParams), forHTTPHeaderField: "Authorization")
        request.setValue(payloadSignature, forHTTPHeaderField: "X-Payload-Signature")
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BitmeshError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BitmeshError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw BitmeshError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }

    private func buildURL(path: String, query: [String: String] = [:]) -> URL {
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = trimmedPath.isEmpty ? trimmedBase : "\(trimmedBase)/\(trimmedPath)"

        guard !query.isEmpty else {
            return URL(string: urlString)!
        }

        var components = URLComponents(string: urlString)!
        components.queryItems = query
            .sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
}
