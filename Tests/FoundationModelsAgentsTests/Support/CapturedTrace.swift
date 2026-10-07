@testable import FoundationModelsAgents
import InMemoryTracing
import Testing
import Tracing
import ULID

/// The spans that ended in one telemetry capture, read as a tree.
///
/// The Router and Extras keep the names and the attribute keys of their spans
/// internal. Thus the reader finds a span of those packages from its place in
/// the tree, or from an id that one of its attributes holds, and not from an
/// attribute key.
struct CapturedTrace {
    /// The name of the span of each submission of a Router session. The Router
    /// keeps its span names internal, thus the test states this name here. The
    /// card of the task names it too.
    static let submissionSpanName = "FoundationModelsRouter.submission"

    /// The spans that ended in the capture, in the order of their end.
    let spans: [FinishedInMemorySpan]

    /// The span of each agent run.
    var runSpans: [FinishedInMemorySpan] {
        spans.filter { $0.operationName == AgentsTelemetry.SpanName.run }
    }

    /// The `agent.message.sent` event of each span, in the order of the end
    /// of the spans.
    var messageEvents: [SpanEvent] {
        spans.flatMap(\.events).filter { $0.name == AgentsTelemetry.EventName.messageSent }
    }

    /// Gives the one span of `run`: the run span whose run id is the id of
    /// `run`.
    ///
    /// - Parameter run: The run.
    /// - Returns: The span.
    /// - Throws: The error of `#require` when the capture holds no span of
    ///   the run.
    func runSpan(of run: AgentRun) throws -> FinishedInMemorySpan {
        let matches = runSpans.filter { span in
            Self.text(of: span, at: AgentsTelemetry.AttributeKey.runID) == run.id.description
        }
        #expect(matches.count == 1)
        return try #require(matches.first)
    }

    /// Gives the parent span of `span`.
    ///
    /// - Parameter span: A span of the capture.
    /// - Returns: The span whose id is the parent id of `span`, or `nil` for
    ///   a root span or for a parent that did not end in the capture.
    func parent(of span: FinishedInMemorySpan) -> FinishedInMemorySpan? {
        spans.first { $0.spanID == span.parentSpanID }
    }

    /// Gives the submission spans of one Router session: each submission span
    /// that holds the id of the session in an attribute.
    ///
    /// - Parameter sessionID: The id of the session.
    /// - Returns: The spans, in the order of their end.
    func submissionSpans(ofSession sessionID: ULID) -> [FinishedInMemorySpan] {
        spans.filter { span in
            span.operationName == Self.submissionSpanName && Self.texts(of: span).contains(sessionID.description)
        }
    }

    /// Gives the string value of one attribute of `span`.
    ///
    /// - Parameters:
    ///   - span: The span.
    ///   - key: The key of the attribute.
    /// - Returns: The string, or `nil` when the span has no such attribute or
    ///   its value is not a string.
    static func text(of span: FinishedInMemorySpan, at key: String) -> String? {
        text(in: span.attributes, at: key)
    }

    /// Gives the string value of one attribute of `event`.
    ///
    /// - Parameters:
    ///   - event: The span event.
    ///   - key: The key of the attribute.
    /// - Returns: The string, or `nil` when the event has no such attribute
    ///   or its value is not a string.
    static func text(of event: SpanEvent, at key: String) -> String? {
        text(in: event.attributes, at: key)
    }

    /// Gives the string value of one attribute of `attributes`.
    ///
    /// - Parameters:
    ///   - attributes: The attributes of a span or of a span event.
    ///   - key: The key of the attribute.
    /// - Returns: The string, or `nil` when there is no such attribute or its
    ///   value is not a string.
    private static func text(in attributes: SpanAttributes, at key: String) -> String? {
        guard case .string(let text) = attributes.get(key) else {
            return nil
        }
        return text
    }

    /// Gives the string value of each attribute of `span`.
    ///
    /// - Parameter span: The span.
    /// - Returns: The strings, in no given order.
    static func texts(of span: FinishedInMemorySpan) -> [String] {
        var texts: [String] = []
        // `SpanAttributes` is not a `Sequence`: `forEach` is its only walk of
        // the attributes, thus no `for` loop compiles here.
        // swift-format-ignore: ReplaceForEachWithForLoop
        span.attributes.forEach { _, value in
            if case .string(let text) = value {
                texts.append(text)
            }
        }
        return texts
    }
}
