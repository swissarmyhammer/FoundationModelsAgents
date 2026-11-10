import FoundationModelsExtras
import Testing

@testable import FoundationModelsAgents

/// One event of the `changes` subscription of the `agents` endpoint, read
/// from a response, and the reads of the endpoint that give the events.
///
/// ``AgentsGraphChangesTests`` and ``AgentsToolWriteTests`` read the change
/// log of a registry through these helpers. Thus the two suites read the
/// cursor and the events with one copy of the GraphQL documents.
struct ChangeEvent {
    /// The selection of each field of an `AgentChange`.
    static let eventFields = "cursor at added changed removed"

    /// The response key of the `changes` subscription.
    static let changesKey = "changes"

    /// The cursor that resumes after the event.
    let cursor: String

    /// The ids of the event.
    let ids: ChangedIDs

    /// Reads the event of a response.
    ///
    /// - Parameters:
    ///   - text: The JSON text of the response.
    ///   - key: The response key of the subscription field.
    /// - Throws: A failed requirement when the response has no event with a
    ///   cursor and a time.
    init(response text: String, at key: String) throws {
        let event = try GraphQLReply(text).object(key)
        cursor = try #require(event["cursor"] as? String)
        _ = try #require(event["at"] as? String)
        ids = ChangedIDs(
            added: event["added"] as? [String] ?? [], changed: event["changed"] as? [String] ?? [],
            removed: event["removed"] as? [String] ?? [])
    }

    /// Queries the root `cursor` of an endpoint.
    ///
    /// - Parameter endpoint: The endpoint.
    /// - Returns: The cursor of the newest change.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   response has no cursor.
    static func cursor(of endpoint: any GraphQLEndpoint) async throws -> String {
        let reply = try GraphQLReply(
            await endpoint.execute(query: "{ cursor }", variables: [:], operationName: nil, viewer: nil))
        return try #require(reply.data?["cursor"] as? String, "no cursor in \(reply.text)")
    }

    /// Gives the first event after a cursor.
    ///
    /// The subscription replays the buffered changes after the cursor at
    /// once. The read also ends when the stream ends, and the test then
    /// fails (test rule T1).
    ///
    /// - Parameters:
    ///   - start: The cursor to resume after.
    ///   - endpoint: The endpoint.
    /// - Returns: The first event after the cursor.
    /// - Throws: The fault of the endpoint, or a failed requirement when the
    ///   stream ends with no event.
    static func first(after start: String, of endpoint: any GraphQLEndpoint) async throws -> ChangeEvent {
        var responses = try await endpoint.subscribe(
            query: "subscription { \(changesKey)(after: \"\(start)\") { \(eventFields) } }", variables: [:],
            operationName: nil, viewer: nil
        ).makeAsyncIterator()
        return try ChangeEvent(response: try #require(try await responses.next()), at: changesKey)
    }
}
