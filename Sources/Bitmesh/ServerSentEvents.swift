import Foundation

/// One server-sent event: an optional `event:` name and its `data:` lines.
public struct ServerSentEvent: Sendable, Equatable {
    /// The `event:` field, when the server named the event (Anthropic does).
    public let event: String?

    /// The `id:` field, when present.
    public let id: String?

    /// The event's `data:` lines, joined with newlines.
    public let data: String

    public init(event: String? = nil, id: String? = nil, data: String) {
        self.event = event
        self.id = id
        self.data = data
    }

    /// True for OpenAI's end-of-stream marker, `data: [DONE]`.
    public var isDone: Bool {
        data.trimmingCharacters(in: .whitespaces) == "[DONE]"
    }

    /// `data` parsed as a JSON object.
    public func json() throws -> BitmeshJSON {
        try JSONHelpers.decodeJSONObject(from: Data(data.utf8))
    }
}

/// Builds events from the lines of a `text/event-stream` body: fields per
/// line, events ended by a blank line, comments (`:`) ignored.
struct ServerSentEventParser {
    private var event: String?
    private var id: String?
    private var data: [String] = []

    /// Feeds one line, without its `\n`. Returns an event when the line ends one.
    mutating func feed(_ rawLine: String) -> ServerSentEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return finish() }
        if line.hasPrefix(":") { return nil }

        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "data": data.append(String(value))
        case "event": event = String(value)
        case "id": id = String(value)
        default: break
        }
        return nil
    }

    /// Ends the current event, if it has data. Call once more at the end of the
    /// body for a last event without a trailing blank line.
    mutating func finish() -> ServerSentEvent? {
        defer {
            event = nil
            data = []
        }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(event: event, id: id, data: data.joined(separator: "\n"))
    }
}
