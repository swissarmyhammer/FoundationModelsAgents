import FoundationModels
import FoundationModelsRouter

/// The signals that decide the end of one run: one stream, and the one
/// continuation that each part of the run yields into.
struct AgentRunSignals: Sendable {
    /// The signals, in the order that the parts of the run gave them.
    let stream: AsyncStream<AgentRunSignal>

    /// The continuation of ``stream``.
    let continuation: AsyncStream<AgentRunSignal>.Continuation

    /// Makes an empty stream of signals.
    init() {
        (stream, continuation) = AsyncStream<AgentRunSignal>.makeStream()
    }
}

extension AgentRun {
    /// Drives the session of the run on the pump of the Router, and gives the
    /// final state of the run (plan.md §8 steps 6 to 8).
    ///
    /// The run subscribes to the session events first, and follows that one
    /// subscription for its whole life (``follow(_:on:)``). It then sends the
    /// task prompt as one message. The pump of the Router runs the answer of
    /// that message, and the answer of each final message of a run that this
    /// run started: each final message is mail, and mail starts an answer
    /// with no call of this run.
    ///
    /// The run ends when its session is idle (``isIdle(on:)``), and the reply
    /// of the last answer is its result. It also ends when the count of
    /// passes goes above the `maxTurns` limit, when an answer fails, when the
    /// Router holds the mail, or when a caller cancels it.
    ///
    /// When the answers end, the run records its final state (``settle(_:)``)
    /// at once. It then cancels its open children and waits for them, waits
    /// until the Router recorded the final message of each child, stops its
    /// session, and closes it. The close finishes the subscription, thus the
    /// follower ends.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The task prompt.
    /// - Returns: The final state: ``AgentRunState/finished(_:)`` with the
    ///   reply of the last answer, ``AgentRunState/cancelled`` for a
    ///   cancelled run, or ``AgentRunState/failed(_:)``.
    func drive(_ session: any RoutedSession, prompt: String) async -> AgentRunState {
        let events = await session.streamSessionEvents()
        async let following: Void = follow(events, on: session)
        let final = settle(await outcome(of: prompt, on: session))
        await children.cancelOpenRuns()
        await sessionWatch.waitForSettlement(ofCalls: children.runs.compactMap(\.context?.completionToken))
        await session.cancel()
        await session.close()
        await following
        return final
    }

    /// Sends the task prompt, and reads the signals of the run until one of
    /// them decides the final state.
    ///
    /// - Parameters:
    ///   - prompt: The task prompt.
    ///   - session: The session of the run.
    /// - Returns: The final state of the run.
    private func outcome(of prompt: String, on session: any RoutedSession) async -> AgentRunState {
        guard !isCancelRequested else {
            return .cancelled
        }
        async let taskAnswer: Void = answerTaskPrompt(prompt, on: session)
        for await signal in signals.stream {
            if let final = await endState(after: signal, on: session) {
                return final
            }
        }
        await taskAnswer
        return .cancelled
    }

    /// Sends the task prompt as one message, and waits for its answer.
    ///
    /// The answer streams its text, thus the progress of the run shows the
    /// text so far. The stream throws the error of a failed answer as it is,
    /// thus a context overflow gives ``AgentRunFailure/contextOverflow(_:)``.
    ///
    /// - Parameters:
    ///   - prompt: The task prompt.
    ///   - session: The session of the run.
    private func answerTaskPrompt(_ prompt: String, on session: any RoutedSession) async {
        do {
            for try await _ in await session.streamEvents(to: prompt) {}
        } catch {
            signals.continuation.yield(.taskAnswerFailed(error))
        }
    }

    /// Gives the final state that `signal` decides, or `nil` when the run
    /// goes on.
    ///
    /// After the count of passes went above the limit, a failed answer does
    /// not decide the final state: the ``AgentRunSignal/limitHit(partial:)``
    /// signal comes after it.
    ///
    /// - Parameters:
    ///   - signal: The signal.
    ///   - session: The session of the run.
    /// - Returns: The final state, or `nil`.
    private func endState(after signal: AgentRunSignal, on session: any RoutedSession) async -> AgentRunState? {
        switch signal {
        case .idle(let text):
            return .finished(text)
        case .limitHit(let partial):
            return .failed(.hitMaxTurns(partial: partial))
        case .cancelRequested:
            await session.cancel()
            return .cancelled
        case .taskAnswerFailed(let error):
            return turns.isLimitHit ? nil : Self.endState(afterTaskFailure: error)
        case .mailAnswerFailed(let reason):
            return turns.isLimitHit ? nil : Self.endState(afterMailFailure: reason)
        case .mailDeliveryPaused(let text):
            await session.cancel()
            return .failed(.mailDeliveryPaused(text))
        case .sessionClosed:
            return .cancelled
        }
    }

    /// Gives the final state of a run whose task answer failed.
    ///
    /// - Parameter error: The error of the answer.
    /// - Returns: ``AgentRunState/cancelled`` for a cancel, else
    ///   ``AgentRunState/failed(_:)`` with the failure of the error.
    private static func endState(afterTaskFailure error: any Error) -> AgentRunState {
        error is CancellationError ? .cancelled : .failed(AgentRunFailure.turnFailure(for: error))
    }

    /// Gives the final state of a run whose answer to a final message failed.
    ///
    /// - Parameter reason: The reason of the failure.
    /// - Returns: ``AgentRunState/cancelled`` for a cancel, else
    ///   ``AgentRunState/failed(_:)`` with ``AgentRunFailure/modelFailed(_:)``.
    private static func endState(afterMailFailure reason: AnswerFailure.Reason) -> AgentRunState {
        switch reason {
        case .cancelled:
            .cancelled
        case .error(let text):
            .failed(.modelFailed(text))
        }
    }

    /// Reads the session-event subscription of the run until it finishes.
    ///
    /// Each event feeds the progress and the answers of the run
    /// (``record(_:)``), the watch that the `agents` tool of the run waits on,
    /// and the count of passes. When the count goes above the limit, the run
    /// stops its session at once. Then each event that decides the end of the
    /// run gives its signal (``signal(after:on:)``).
    ///
    /// - Parameters:
    ///   - events: The session-event subscription of the run, made before
    ///     the task prompt. The session finishes it when the run closes it.
    ///   - session: The session of the run.
    private func follow(_ events: AsyncStream<SessionEvent>, on session: any RoutedSession) async {
        for await event in events {
            record(event)
            sessionWatch.observe(event)
            if turns.apply(event) {
                await session.cancel()
            }
            if let signal = await signal(after: event, on: session) {
                signals.continuation.yield(signal)
            }
        }
        sessionWatch.finish()
        signals.continuation.yield(.sessionClosed)
        signals.continuation.finish()
    }

    /// Gives the signal of one session event, or `nil` for an event that
    /// decides nothing.
    ///
    /// - The end of an answer gives ``AgentRunSignal/limitHit(partial:)``
    ///   after the count went above the limit. Else an answer gives
    ///   ``AgentRunSignal/idle(_:)`` when the session is idle.
    /// - A failed answer to mail alone gives
    ///   ``AgentRunSignal/mailAnswerFailed(_:)``. A failed answer of the task
    ///   prompt gives nothing here: its error comes from its own stream.
    /// - A hold of the mail gives ``AgentRunSignal/mailDeliveryPaused(_:)``.
    ///
    /// - Parameters:
    ///   - event: The event, already recorded.
    ///   - session: The session of the run.
    /// - Returns: The signal, or `nil`.
    private func signal(after event: SessionEvent, on session: any RoutedSession) async -> AgentRunSignal? {
        if case .answered(let answer) = event {
            if turns.isLimitHit {
                return .limitHit(partial: answer.reply)
            }
            return await isIdle(on: session) ? .idle(answer.reply) : nil
        }
        if case .answerFailed(let failure) = event {
            if turns.isLimitHit {
                return .limitHit(partial: answers.partial)
            }
            return failure.messageIds.isEmpty ? .mailAnswerFailed(failure.reason) : nil
        }
        if case .mailDeliveryPaused(let pause) = event {
            return .mailDeliveryPaused(pause.description)
        }
        return nil
    }

    /// Tells if the session of the run is idle after an answer.
    ///
    /// The session is idle when each run that this run started ended, when
    /// no message waits, and when the session delivered the final message of
    /// each of those runs: the text of each final message is in a prompt of
    /// the settled transcript. The last answer came after that prompt, thus
    /// it answered each final message.
    ///
    /// The check reads the transcript, not the order of the events. The
    /// Router stages a final message before it sends its
    /// ``SessionEvent/runSettled(_:)``, thus a submission can deliver a final
    /// message before that event.
    ///
    /// - Parameter session: The session of the run.
    /// - Returns: `true` when the session is idle.
    private func isIdle(on session: any RoutedSession) async -> Bool {
        let children = children.runs
        guard children.allSatisfy({ $0.state != .running }) else {
            return false
        }
        let depth = await session.messageQueueDepth()
        guard depth.waiting == 0 else {
            return false
        }
        guard !children.isEmpty else {
            return true
        }
        let prompts = Self.promptTexts(in: await session.transcript)
        return children.allSatisfy { child in
            let finalMessage = child.report
            return prompts.contains { $0.contains(finalMessage) }
        }
    }

    /// Gives the text of each prompt of `transcript`.
    ///
    /// - Parameter transcript: A transcript of the session.
    /// - Returns: The text segments of each prompt, joined, in transcript
    ///   order.
    static func promptTexts(in transcript: Transcript) -> [String] {
        transcript.compactMap { entry in
            guard case .prompt(let prompt) = entry else {
                return nil
            }
            return prompt.segments.compactMap(Self.text(of:)).joined()
        }
    }

    /// Gives the text of one segment.
    ///
    /// - Parameter segment: A segment of a prompt.
    /// - Returns: The text of a text segment, or `nil` for each other
    ///   segment.
    private static func text(of segment: Transcript.Segment) -> String? {
        guard case .text(let text) = segment else {
            return nil
        }
        return text.content
    }
}
