import FoundationModelsRouter

/// The final message of a run and the texts that tell its state
/// (plan.md §9.1, §9.2).
///
/// A run that a tool call started posts one `.completed` `OperationEvent`
/// through the `ToolContext` of that call when its turn ends. The Router
/// journals the post into the transcript of the caller and stages it, and
/// the next prompt of the caller reads it. The run posts nothing else.
extension AgentRun {
    /// The words that name the run in each text: "Agent `name` (`id`)".
    var subject: String {
        "Agent \(agent.id) (\(id))"
    }

    /// The text that tells the state of the run, as `check agent` gives it.
    ///
    /// - A run in operation: "Agent `name` (`id`) is running: `lastEvent`."
    /// - A finished run: "Agent `name` (`id`) finished.", then the full text
    ///   of its last turn.
    /// - A failed or a cancelled run: the detail of its final message.
    var report: String {
        report(of: state)
    }

    /// Gives the text that tells `state`.
    ///
    /// - Parameter state: A state of this run.
    /// - Returns: The text of ``report`` for `state`.
    func report(of state: AgentRunState) -> String {
        switch state {
        case .running:
            "\(subject) is running: \(lastEvent)."
        case .finished(let text):
            "\(subject) finished.\n\n\(text)"
        case .failed(let failure):
            failedText(for: failure)
        case .cancelled:
            cancelledText
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

    /// Gives the final message of the run for `state`.
    ///
    /// The event is always `.completed`, because only a `.completed` event is
    /// a terminal that makes the caller run a turn:
    ///
    /// - Finished: the `detail` is the full text of the last turn, and the
    ///   `outcome` is `.succeeded`.
    /// - Failed: "Agent `name` (`id`) failed: reason.", and `.failed`.
    /// - Cancelled: "Agent `name` (`id`) was cancelled.", and `.cancelled`.
    ///
    /// The event has the stamps of the tool call that started the run. A
    /// host-driven run has no such call, thus its event has the name of the
    /// tool, the op of `start agent`, and the id of the run. `ToolContext`
    /// stamps each post again, thus the stamps here matter only to a reader
    /// of the event itself.
    ///
    /// - Parameter state: A state of this run.
    /// - Returns: The event, or `nil` for ``AgentRunState/running``.
    func finalMessage(for state: AgentRunState) -> OperationEvent? {
        let ending: (detail: String, outcome: OperationOutcome)
        switch state {
        case .running:
            return nil
        case .finished(let text):
            ending = (text, .succeeded)
        case .failed(let failure):
            ending = (failedText(for: failure), .failed)
        case .cancelled:
            ending = (cancelledText, .cancelled)
        }
        return OperationEvent(
            tool: context?.tool ?? ToolVocabulary.agentsToolName,
            op: context?.op ?? StartAgent.opString,
            correlationID: context?.completionToken ?? id.description,
            kind: .completed,
            detail: ending.detail,
            outcome: ending.outcome)
    }

    /// Posts the final message for `final` one time through the context of
    /// the tool call that started the run.
    ///
    /// A host-driven run has no context, thus it posts nothing.
    ///
    /// - Parameter final: The final state of the run.
    func postFinalMessage(for final: AgentRunState) async {
        guard let context, let message = finalMessage(for: final) else {
            return
        }
        await context.post(message)
    }
}
