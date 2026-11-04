import Foundation
import FoundationModelsExtras
import Logging
import FoundationModelsRouter
import ULID

/// The typed record that `send agent` and `send caller` give the host for each message that
/// they send as mail.
///
/// The call attaches it to its tool-call report (`ToolContext.attach(_:)`). The host reads it
/// from `SessionEvent.toolCallReport`, and tells the messages between a caller and a child
/// session apart with it. The model never sees it, and it holds no message text.
///
/// The JSON document has these keys:
/// - `mailId`: string. The ULID of the mail in the session of the receiver.
/// - `direction`: string. `toChild` for `send agent`, `toCaller` for `send caller`.
/// - `receiverRunId`: string, only for `toChild`. The id of the run that got the message.
/// - `receiverSessionId`: string. The ULID of the session that got the mail.
struct AgentMessageSent: Codable, Equatable, Sendable {
    /// The name of the type in ``ToolCallAttachment/schemaName``.
    static let schemaName = "FoundationModelsAgents.AgentMessageSent"

    /// The direction of the message.
    enum Direction: String, Codable, Sendable {
        /// From a caller to a run that it started (`send agent`).
        case toChild

        /// From a run to the session that started it (`send caller`).
        case toCaller
    }

    /// The ULID of the mail in the session of the receiver.
    let mailId: String

    /// Where the message went.
    let direction: Direction

    /// The id of the run that got the message, or `nil` for a message to a caller.
    let receiverRunId: String?

    /// The ULID of the session that got the mail.
    let receiverSessionId: String

    /// Attaches the record to the current tool call. A call with no bound `ToolContext`, for
    /// example a call of the tool outside a Router session, attaches nothing.
    ///
    /// - Parameters:
    ///   - mailID: The id of the mail.
    ///   - direction: Where the message went.
    ///   - receiverRunID: The run that got the message, for a message to a child.
    ///   - receiverSession: The session that got the mail.
    ///   - logger: The logger that tells when the record cannot be encoded.
    static func attach(
        mailID: MailID, direction: Direction, receiverRunID: ULID?, receiverSession: ULID, logger: Logger
    ) {
        let record = AgentMessageSent(
            mailId: mailID.value.description, direction: direction, receiverRunId: receiverRunID?.description,
            receiverSessionId: receiverSession.description)
        guard let data = try? JSONEncoder().encode(record), let json = String(data: data, encoding: .utf8) else {
            assertionFailure("The sent-message record of strings did not encode.")
            logger.error("\(AgentsTelemetry.LogMessage.messageRecordNotEncoded)")
            return
        }
        ToolContext.current?.attach(ToolCallAttachment(schemaName: schemaName, contentJSON: json))
    }
}
