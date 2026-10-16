@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the Router contract of `cancelAll()` on the session of a lead run that
/// has an open child: the call returns its `SignalID` at once, the signal ends
/// before the child ends, and the recorded terminal of the `start agent` call
/// holds the final message of the child.
///
/// The order of each step is fixed. The child holds its turn on a gate with
/// a ``ScriptedAgentStep/holdThroughCancel(_:)`` step: a cancel does not
/// release the step, only ``ScriptedGate/open()`` does. The child closes its
/// session before it ends, and the close waits for the held turn. Thus the
/// child stays ``AgentRunState/running`` until the test opens the gate, and
/// the body of the `start agent` call, which waits for the end of the child,
/// cannot settle the call before that.
///
/// The test calls `cancelAll()` only after the task answer of the lead ended.
/// The run event observer opens a gate at the `answered` event of the lead.
/// The end of the lead also opens that gate, thus a lead that fails before
/// that event does not hold the test. A `cancelAll()` in an answer stops that
/// answer, and the session then sends no live event that the work of that
/// answer posts. The `start agent` call is work of the task answer. Thus the
/// order of the end of the answer and of `cancelAll()` must be fixed. The
/// test uses no clock and no poll.
@Suite("cancelAll() and the final message of a child")
struct CancelAllFinalMessageTests {
    @Test("cancelAll() returns its SignalID before the child ends, and the recorded terminal of the start agent call has the final message")
    func cancelAllKeepsTheFinalMessageOfTheChild() async throws {
        let gate = ScriptedGate()
        let leadAnswered = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                NestedRunTests.parentPlay(NestedRunTests.leadKey, children: [(NestedRunTests.reviewer, NestedRunTests.reviewerKey)]),
                ScriptedAgentPlay(
                    key: NestedRunTests.reviewerKey,
                    steps: [.holdThroughCancel(gate), .finalText(NestedRunTests.reviewerText)])
            ]),
            runEventObserver: { run, output in
                if run.agent.id == NestedRunTests.lead, case .answered = output.event {
                    leadAnswered.open()
                }
            })
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
        try await leadAnswered.wait(orEndOf: lead)
        try #require(await gate.waitForArrival(orEndOf: lead))
        let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)
        let leadSession = try #require(lead.heldSession)
        let events = await leadSession.streamSessionEvents()

        let signal = leadSession.cancelAll()
        let stateAfterCancelAll = child.state
        await gate.waitForCancel()
        let signalEnd = try await leadSession.awaitTerminal(of: signal)
        let stateAtSignalEnd = child.state
        gate.open()
        let childFinal = await child.finalState()
        let settled = try await NestedRunTests.settlement(of: child, in: events)
        // A stopped run makes no mail, thus the lead never answers the final
        // message. The lead can go idle after the end of the call of the
        // child (`leadGoesIdleAfterCancelAllStoppedTheChild`), or the cancel
        // of the lead ends it. This test pins the recording, not that choice.
        lead.cancel()
        _ = await lead.finalState()
        let posts = try NestedRunTests.posts(of: child, in: lead.recordingDirectory)
        let cancelledText = child.report(of: .cancelled)

        #expect(stateAfterCancelAll == .running)
        #expect(signalEnd == .signalDone(signal))
        #expect(stateAtSignalEnd == .running)
        #expect(childFinal == .cancelled)
        #expect(settled.detail == cancelledText)
        #expect(posts.map(\.detail) == [cancelledText])
    }

    /// The order of each step is fixed, as in
    /// `cancelAllKeepsTheFinalMessageOfTheChild`: the test calls `cancelAll()`
    /// on the session of the lead after the task answer of the lead ended,
    /// while the child holds through the cancel. `cancelAll()` cancels the
    /// queued run mail of the child (each such mail gets its `cancelled`
    /// terminal event), and the stopped child makes no more mail. The test
    /// then opens the gate of the child, and calls no cancel on the lead.
    ///
    /// The idle rule of the lead goes by id: each mail of the child has a
    /// terminal event, and the call of the child closes when the child ends.
    /// Thus the lead does not wait for mail of the child, and ends by itself
    /// with the reply of its task answer.
    @Test("after cancelAll() stopped the child, the lead waits for no mail of the child: it goes idle and finishes")
    func leadGoesIdleAfterCancelAllStoppedTheChild() async throws {
        let gate = ScriptedGate()
        let leadAnswered = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                NestedRunTests.parentPlay(NestedRunTests.leadKey, children: [(NestedRunTests.reviewer, NestedRunTests.reviewerKey)]),
                ScriptedAgentPlay(
                    key: NestedRunTests.reviewerKey,
                    steps: [.holdThroughCancel(gate), .finalText(NestedRunTests.reviewerText)])
            ]),
            runEventObserver: { run, output in
                if run.agent.id == NestedRunTests.lead, case .answered = output.event {
                    leadAnswered.open()
                }
            })
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
        try await leadAnswered.wait(orEndOf: lead)
        try #require(await gate.waitForArrival(orEndOf: lead))
        let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)
        let leadSession = try #require(lead.heldSession)

        leadSession.cancelAll()
        await gate.waitForCancel()
        gate.open()
        let childFinal = await child.finalState()
        let leadFinal = await lead.finalState()

        #expect(childFinal == .cancelled)
        #expect(leadFinal == .finished(NestedRunTests.startedText))
    }

    /// The order of each step is fixed. The task answer of the lead calls
    /// `start agent`, and the call answers at once with the pending envelope
    /// (the settle period of the harness is 0). The next step of the lead is
    /// a ``ScriptedAgentStep/holdThroughCancel(_:)`` step, thus the task
    /// answer is still open when the lead arrives at its gate. The child
    /// holds on its own gate in the same way. The test calls `cancelAll()`
    /// on the lead session while both hold. It opens each gate only after
    /// the cancel arrived at that gate (``ScriptedGate/waitForCancel()``).
    ///
    /// The `cancelAll()` stops the open task answer. The session then sends
    /// no live event that the work of that answer posts, also not the
    /// `runSettled` of the `start agent` call. Thus the test does not wait
    /// for that event. It waits for the end of the lead, and then reads the
    /// recording of the lead.
    @Test("cancelAll() while the answer that started a child still runs: the run ends, and the recording of the parent holds the final message of the child")
    func cancelAllInTheOpenAnswerEndsTheRunAndKeepsTheFinalMessage() async throws {
        let leadGate = ScriptedGate()
        let childGate = ScriptedGate()
        let harness = try await AgentRunHarness.make(
            script: ScriptedAgentScript([
                ScriptedAgentPlay(
                    key: NestedRunTests.leadKey,
                    steps: [
                        NestedRunTests.startStep(NestedRunTests.reviewer, prompt: NestedRunTests.reviewerKey),
                        .holdThroughCancel(leadGate),
                        .finalText(NestedRunTests.startedText)
                    ]),
                ScriptedAgentPlay(
                    key: NestedRunTests.reviewerKey,
                    steps: [.holdThroughCancel(childGate), .finalText(NestedRunTests.reviewerText)])
            ]))
        defer { try? harness.delete() }
        let runner = harness.makeRunner()

        let lead = try await runner.start(NestedRunTests.lead, prompt: NestedRunTests.leadKey)
        try #require(await leadGate.waitForArrival(orEndOf: lead))
        try harness.script.requirePendingStarts()
        await childGate.waitForArrival()
        let child = try await NestedRunTests.onlyRun(of: runner, caller: lead.id)
        let leadSession = try #require(lead.heldSession)

        leadSession.cancelAll()
        await leadGate.waitForCancel()
        await childGate.waitForCancel()
        leadGate.open()
        childGate.open()
        let leadFinal = await lead.finalState()
        let childFinal = await child.finalState()
        let posts = try NestedRunTests.posts(of: child, in: lead.recordingDirectory)

        #expect(leadFinal == .cancelled)
        #expect(childFinal == .cancelled)
        #expect(posts.map(\.detail) == [child.report(of: .cancelled)])
    }
}
