import FoundationModelsExtras
import FoundationModelsRouter
import ULID

/// The final message of a run and the texts that tell its state.
///
/// The `agents` tool is a background tool of the Router. The background body
/// of a `start agent` call waits for the run, and gives the final message
/// text of the run as the detail of the Router run. The Router then records
/// the `.completed` terminal of the call in the transcript of the caller,
/// and delivers it to the caller as mail. The run itself posts nothing.
extension AgentRun {
    /// The words that name the run in each text: "Agent `name` (`id`)".
    var subject: String {
        "Agent \(agent.id) (\(id))"
    }

    /// The text that tells the state of the run, as `check agent` gives it.
    ///
    /// - A run in operation: "Agent `name` (`id`) is still working." After
    ///   the answer of its task prompt, while runs that it started are open,
    ///   then "It waits for `N` agents that it started." While the Router
    ///   holds the mail of the run, then ``pausedSentence``. Then, on the next
    ///   line, `PendingRunEnvelope.pendingWorkInstruction` of
    ///   FoundationModelsExtras: the result comes as a new message, thus the
    ///   caller does not check again. That package owns the one copy of the
    ///   text. Then the lines of its progress (``AgentRunProgress/text``):
    ///   the one progress line, and the last message of each running child.
    ///   The text reads only the locks of the run, thus it never waits for
    ///   an answer.
    /// - A finished run: "Agent `name` (`id`) finished.", then the full reply
    ///   of its last answer. This is the final message text.
    /// - A failed or a cancelled run: the text of its final message.
    var report: String {
        report(of: state)
    }

    /// The sentence that leads a repeated `check agent` text of a run in
    /// operation when nothing changed after the last check of the same
    /// caller.
    static let unchangedCheckSentence = "You checked this agent before, and nothing changed."

    /// Gives the text of ``report`` for a `check agent` call by `caller`.
    ///
    /// The run keeps the last text of the run in operation that each caller
    /// got (``recordCheck(_:by:)``). When `caller` gets the same text again,
    /// thus nothing changed after its last check, the text starts with
    /// ``unchangedCheckSentence``. The text of a run that ended does not
    /// change.
    ///
    /// - Parameter caller: The session id of the caller, or `nil` for a call
    ///   outside a Router session.
    /// - Returns: The text of the state of the run for this check.
    func checkReport(by caller: ULID?) -> String {
        let state = self.state
        guard state == .running else {
            return report(of: state)
        }
        let text = runningText
        return recordCheck(text, by: caller) ? "\(Self.unchangedCheckSentence) \(text)" : text
    }

    /// Gives the text that tells `state`.
    ///
    /// - Parameter state: A state of this run.
    /// - Returns: The text of ``report`` for `state`.
    func report(of state: AgentRunState) -> String {
        switch state {
        case .running:
            runningText
        case .finished(let text):
            "\(subject) finished.\n\n\(text)"
        case .failed(let failure):
            failedText(for: failure)
        case .cancelled:
            cancelledText
        }
    }

    /// The text of a run in operation: the heading line, the shared
    /// pending-work instruction, then the lines of its progress.
    private var runningText: String {
        let heading = ["\(subject) is still working.", waitingSentence, pausedSentence].compactMap(\.self)
            .joined(separator: " ")
        return [heading, PendingRunEnvelope.pendingWorkInstruction, progress.text].joined(separator: "\n")
    }

    /// The sentence that `check agent` adds while the Router holds the mail
    /// of the run (``pause``): "It is paused: `description`. It waits for `N`
    /// agents that it started, then it ends with their results. A message
    /// from its caller lets it continue." `nil` when the run is not paused.
    var pausedSentence: String? {
        pause.map { pause in
            "It is paused: \(pause.description). It waits for \(pause.openChildren) agents that it started, "
                + "then it ends with their results. A message from its caller lets it continue."
        }
    }

    /// The text of a cancelled run: "Agent `name` (`id`) was cancelled."
    private var cancelledText: String {
        "\(subject) was cancelled."
    }

    /// Gives the text of a failed run.
    ///
    /// - Parameter failure: The reason that the run failed.
    /// - Returns: "Agent `name` (`id`) failed: reason."
    private func failedText(for failure: AgentRunFailure) -> String {
        "\(subject) failed: \(failure.reason)."
    }

    /// Gives the final message of the run for `state`, as a `.completed`
    /// event.
    ///
    /// `cancel agent` gives this event for a run that ended before the
    /// cancel. The `detail` is the ``report(of:)`` of `state`, thus it names
    /// the agent and the run, the same as `check agent`:
    ///
    /// - Finished: "Agent `name` (`id`) finished.", then the full reply of the
    ///   last answer, and the `outcome` is `.succeeded`.
    /// - Failed: "Agent `name` (`id`) failed: reason.", and `.failed`.
    /// - Cancelled: "Agent `name` (`id`) was cancelled.", and `.cancelled`.
    ///
    /// The event has the stamps of the tool call that started the run. A
    /// host-driven run has no such call, thus its event has the name of the
    /// tool, the op of `start agent`, and the id of the run.
    ///
    /// - Parameter state: A state of this run.
    /// - Returns: The event, or `nil` for ``AgentRunState/running``.
    func finalMessage(for state: AgentRunState) -> OperationEvent? {
        let outcome: OperationOutcome
        switch state {
        case .running:
            return nil
        case .finished:
            outcome = .succeeded
        case .failed:
            outcome = .failed
        case .cancelled:
            outcome = .cancelled
        }
        return OperationEvent(
            tool: context?.tool ?? ToolVocabulary.agentsToolName,
            op: context?.op ?? StartAgent.opString,
            correlationID: context?.completionToken ?? id.description,
            kind: .completed,
            detail: report(of: state),
            outcome: outcome)
    }
}
