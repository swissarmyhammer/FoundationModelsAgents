import FoundationModelsExtras
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

/// Two points in the idle rule of a run where a test can hold the run
/// (``AgentRun/install(_:)``). A test uses them to put a message at an
/// exact point of the idle rule, with no dependency on timing. A run that
/// no test changes has hooks that do nothing.
struct AgentRunIdleHooks: Sendable {
    /// Runs at the start of each idle check, before the run reads the
    /// mail queue of its session. The check of a paused run, whether its
    /// wait ended, also runs it.
    var beforeIdleCheck: @Sendable () async -> Void = {}

    /// Runs after the run got an idle signal, before the run decides to end
    /// on it.
    var beforeIdleSettle: @Sendable () async -> Void = {}
}

extension AgentRun {
    /// Drives the session of the run on the pump of the Router, and gives the
    /// final state of the run.
    ///
    /// The run subscribes to the session events first, and follows that one
    /// subscription for its whole life
    /// (``follow(_:on:answersQuestions:observer:)``). It then mails the task
    /// prompt as one user message, and at once after it each
    /// message from the caller that it held (``mailTaskPrompt(_:to:)``). It
    /// waits for the answer of the task prompt by its mail id, and for the
    /// answer of each message from the caller by its mail id
    /// (``awaitAnswer(ofCallerMessage:on:)``). The pump of the Router runs the
    /// answer of that mail, and the answer of each final message of a run
    /// that this run started: each final message is mail, and mail starts an
    /// answer with no call of this run.
    ///
    /// The run ends when its session is idle (``acceptedMessagesIfIdle(on:)``)
    /// and no message from the caller arrived after the idle check
    /// (``settle(idle:acceptedMessages:)``). The reply of the last answer is
    /// then its result. The run also ends when the count of passes goes above
    /// the `maxTurns` limit, when an answer fails, when the Router holds the
    /// mail, or when a caller cancels it.
    ///
    /// When the answers end, the run records its final state (``settle(_:)``)
    /// at once. It then cancels its open children and waits for them, waits
    /// until the run plane settled the call of each child, and closes its
    /// session. The wait for the calls goes by token through the run plane
    /// (``ParentSessionWatch/waitForSettlement(ofCalls:)``). It does not use
    /// the live ``SessionEvent/runSettled(_:)``, because a cancel can drop
    /// that event. The close stops all work of the session first
    /// (`cancelAll()`), and finishes the subscription, thus the follower
    /// ends. The close also waits for each run body
    /// (`RunPlane.joinRunBodies()`), and the body of each call writes its
    /// terminal to the journal before it ends. Thus the recording of the
    /// session holds the final message of each child.
    ///
    /// A run with an interactive question target sends each question of its
    /// session one level up (`SubagentQuestionRelay`). Under a headless
    /// target the session of the run is headless too: each question ends at
    /// once with a cancel, thus the run starts no relay. The relay subscribes
    /// to the session before the task prompt, thus it gets each question. An
    /// answer at the target goes down to the session, and each end of the
    /// question ends it at each level. After the close of the session, the run waits
    /// until the relay read the events of the session to their end
    /// (`SubagentQuestionRelay.finish()`). The close of the session bounds
    /// this wait, also for a cancelled run. Then the drive ends, and the run
    /// lets go of the target: the target holds the calling session.
    ///
    /// - Parameters:
    ///   - session: The session of the run.
    ///   - prompt: The task prompt.
    ///   - questionTarget: The run of the session that started this run,
    ///     where the run sends the questions of its session, or `nil` (the
    ///     default). A run with no target answers each question itself
    ///     (``answerQuestion(of:on:)``).
    ///   - observer: The observer of the session events of the host
    ///     (``AgentEnvironment/runEventObserver``), or `nil`.
    /// - Returns: The final state: ``AgentRunState/finished(_:)`` with the
    ///   reply of the last answer, ``AgentRunState/cancelled`` for a
    ///   cancelled run, or ``AgentRunState/failed(_:)``.
    func drive(
        _ session: any RoutedSession, prompt: String, questionTarget: SubagentQuestionTarget? = nil,
        observer: AgentEnvironment.RunEventObserver? = nil
    ) async -> AgentRunState {
        let events = await session.streamSessionEvents()
        var relay: SubagentQuestionRelay?
        if let questionTarget, questionTarget.userPresence == .interactive {
            relay = await SubagentQuestionRelay.start(child: session, agentName: agent.id, target: questionTarget)
        }
        async let following: Void = follow(
            events, on: session, answersQuestions: questionTarget == nil, observer: observer)
        let final = settle(await outcome(of: prompt, on: session))
        await children.cancelOpenRuns()
        await sessionWatch.waitForSettlement(ofCalls: children.runs.compactMap(\.context))
        await session.close()
        await following
        await relay?.finish()
        return final
    }

    /// Sends the task prompt, and reads the signals of the run until one of
    /// them decides the final state.
    ///
    /// The first signal that decides a final state wins: the call returns
    /// it, and reads no more signals. Thus a signal that comes after that
    /// time does not change the final state, for example a
    /// `MailRefusal.closed` or a `CancellationError` of a wait for an answer
    /// when the run closes its session. One failed answer can give two
    /// signals: a chain that holds the task prompt and a message from the
    /// caller gives ``AgentRunSignal/taskAnswerFailed(_:)`` and
    /// ``AgentRunSignal/callerAnswerFailed(_:)`` with the same error. Both
    /// give the same final state, and only the first decides it.
    ///
    /// - Parameters:
    ///   - prompt: The task prompt.
    ///   - session: The session of the run.
    /// - Returns: The final state of the run.
    private func outcome(of prompt: String, on session: any RoutedSession) async -> AgentRunState {
        guard !isCancelRequested else {
            return .cancelled
        }
        let taskMailID = mailTaskPrompt(prompt, to: session)
        async let taskAnswer: Void = answerTaskPrompt(taskMailID, on: session)
        for await signal in signals.stream {
            if let final = await endState(after: signal, on: session) {
                return final
            }
        }
        await taskAnswer
        return .cancelled
    }

    /// Mails the task prompt as one user message in stream mode, and then
    /// mails each message from the caller that the run held
    /// (``releaseHeldMessages(to:)``). The follower subscribed to the
    /// session events before this call
    /// (``drive(_:prompt:questionTarget:observer:)``).
    ///
    /// The task prompt is the first mail of the session. The run held each
    /// message from the caller until this time, and mails the held messages
    /// at once after the task prompt. The mail queue is first in, first out,
    /// thus the session gets them after the task prompt.
    ///
    /// When the session refuses the task prompt, the run gets
    /// ``AgentRunSignal/taskAnswerFailed(_:)`` with the refusal, and the
    /// held messages stay held.
    ///
    /// - Parameters:
    ///   - prompt: The task prompt.
    ///   - session: The session of the run.
    /// - Returns: The id of the task prompt, or `nil` when the session
    ///   refused it.
    private func mailTaskPrompt(_ prompt: String, to session: any RoutedSession) -> MailID? {
        let taskMail = Mail(
            sender: .user, body: .userMessage(prompt: prompt, options: UserMessageOptions(maxTokens: nil, mode: .stream)))
        if let refusal = mailUserTypeMail(taskMail, to: session) {
            signals.continuation.yield(.taskAnswerFailed(refusal))
            return nil
        }
        releaseHeldMessages(to: session)
        return taskMail.id
    }

    /// Waits for the answer of the task prompt.
    ///
    /// The run waits on the id only after ``mailTaskPrompt(_:to:)`` mailed
    /// it. The wait throws the error of a failed answer as it is, thus a
    /// context overflow gives ``AgentRunFailure/contextOverflow(_:)``.
    ///
    /// - Parameters:
    ///   - taskMailID: The id of the task prompt, or `nil` when the session
    ///     refused it. The run then got its signal already.
    ///   - session: The session of the run.
    private func answerTaskPrompt(_ taskMailID: MailID?, on session: any RoutedSession) async {
        guard let taskMailID else { return }
        do {
            _ = try await session.awaitAnswer(of: taskMailID)
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
        case .idle(let text, let acceptedMessages):
            await idleHooks.beforeIdleSettle()
            return settle(idle: .finished(text), acceptedMessages: acceptedMessages)
        case .limitHit(let partial):
            return .failed(.hitMaxTurns(partial: partial))
        case .cancelRequested:
            session.cancelAll()
            return .cancelled
        case .taskAnswerFailed(let error), .callerAnswerFailed(let error):
            return turns.isLimitHit ? nil : Self.endState(afterAnswerFailure: error)
        case .mailAnswerFailed(let reason):
            return turns.isLimitHit ? nil : Self.endState(afterMailFailure: reason)
        case .mailDeliveryPaused, .pauseDrained:
            return await endStateIfDrained(on: session)
        case .sessionClosed:
            return .cancelled
        }
    }

    /// Gives the final state of a paused run when its wait ended, or `nil`
    /// when the run goes on.
    ///
    /// While the Router holds the mail (``pauseDescription``), the run starts
    /// no answer and no new run, and it does not stop its children. It waits
    /// until each run that it started ended and each call closed. Then it
    /// ends as ``AgentRunFailure/mailDeliveryPaused(_:)``, with the held
    /// results (``heldResults(after:)``). The wait goes on while an answer is
    /// open, or while a message from the caller is on its way to the queue
    /// or waits in it: that message ends the hold, and the run goes on. The
    /// record of the final state goes through
    /// ``settle(idle:acceptedMessages:)``, thus a message that the run
    /// accepts after the check keeps the run in operation.
    ///
    /// - Parameter session: The session of the run.
    /// - Returns: The final state, or `nil`.
    private func endStateIfDrained(on session: any RoutedSession) async -> AgentRunState? {
        await idleHooks.beforeIdleCheck()
        guard let pause = pauseDescription, !isSettled, !answers.isAnswerOpen, children.openCount == 0,
            sessionWatch.isEachCallClosed, let acceptedMessages = acceptedMessagesWhenNoneInbound
        else {
            return nil
        }
        let depth = await session.mailQueueDepth()
        guard Self.userTypeKinds.allSatisfy({ (depth.depthByKind[$0] ?? 0) == 0 }),
            await session.openElicitationIds().isEmpty
        else {
            return nil
        }
        return settle(idle: .failed(.mailDeliveryPaused(heldResults(after: pause))), acceptedMessages: acceptedMessages)
    }

    /// Gives the text of a paused run at its end: the description of the
    /// hold, then the final message of each run that it started whose mail
    /// the Router held, in the order of the starts.
    ///
    /// The mail of a child is held when the mail of the call of that child
    /// has no terminal event (``ParentSessionWatch/hasTerminal(forEachMailOfCalls:and:)``).
    /// The text of each held child is its ``report``: "Agent `name` (`id`)
    /// finished.", then its final text, or the text of its failure or of its
    /// cancel.
    ///
    /// - Parameter pause: The description of the hold.
    /// - Returns: The text.
    private func heldResults(after pause: String) -> String {
        let held = children.runs.filter { child in
            guard let token = child.context?.completionToken else {
                return false
            }
            return !sessionWatch.hasTerminal(forEachMailOfCalls: [token], and: [MailID]())
        }
        guard !held.isEmpty else {
            return pause
        }
        return ([pause, Self.heldResultsHeading] + held.map(\.report)).joined(separator: "\n\n")
    }

    /// The line before the held results in the text of a paused run.
    static let heldResultsHeading = "The final messages that the session held:"

    /// Gives the final state of a run whose answer to the task prompt or to
    /// a message from the caller failed.
    ///
    /// - Parameter error: The error of the answer.
    /// - Returns: ``AgentRunState/cancelled`` for a cancel, else
    ///   ``AgentRunState/failed(_:)`` with the failure of the error.
    private static func endState(afterAnswerFailure error: any Error) -> AgentRunState {
        error is CancellationError ? .cancelled : .failed(AgentRunFailure.turnFailure(for: error))
    }

    /// Gives the final state of a run whose answer to mail alone failed.
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
    /// The observer of the host gets each event first, synchronously, before
    /// the run uses it. Each event then feeds the progress and the answers of
    /// the run (``record(_:)``), the watch of the mail and of the tool calls
    /// of the session (``ParentSessionWatch/observe(_:)``), and the count of
    /// passes. Then each event that decides the end of the run gives its
    /// signal (``signal(after:on:)``).
    ///
    /// When the count goes above the limit, the run stops its session with
    /// `cancelAll()`. ``AgentRunLimitStop`` decides the time of that stop
    /// from each event and each signal.
    ///
    /// - Parameters:
    ///   - events: The session-event subscription of the run, made before
    ///     the task prompt. The session finishes it when the run closes it.
    ///   - session: The session of the run.
    ///   - answersQuestions: `true` when the run has no question target, and
    ///     answers each question of its session itself
    ///     (``answerQuestion(of:on:)``). `false` when the relay sends each
    ///     question to the target.
    ///   - observer: The observer of the session events of the host, or
    ///     `nil`.
    private func follow(
        _ events: AsyncStream<SessionOutput>, on session: any RoutedSession, answersQuestions: Bool,
        observer: AgentEnvironment.RunEventObserver?
    ) async {
        var limitStop = AgentRunLimitStop()
        for await output in events {
            observer?(self, output)
            let event = output.event
            record(event)
            sessionWatch.observe(output)
            if answersQuestions, case .elicitationRequested(let operation) = event {
                await answerQuestion(of: operation, on: session)
            }
            if limitStop.action(after: event, wentAboveLimit: turns.apply(event)) == .stop {
                session.cancelAll()
            }
            if let signal = await signal(after: event, on: session) {
                if limitStop.action(at: signal) == .stop {
                    session.cancelAll()
                }
                signals.continuation.yield(signal)
            }
        }
        signals.continuation.yield(.sessionClosed)
        signals.continuation.finish()
    }

    /// Answers one question of the session of the run at once, with a cancel
    /// that gives `RunPlane.noUserPresentReason`.
    ///
    /// A run that a `start agent` call started sends its questions to the
    /// session of that call (``drive(_:prompt:questionTarget:observer:)``),
    /// and does not use this guard. The session of a run with no question
    /// target, for example a host-started run, is headless
    /// (``AgentEnvironment/runUserPresence``): no user can answer its
    /// question, thus the question ends at once and sends no event. This
    /// guard answers a question that still comes, for example from a run
    /// session that a test made interactive. Thus no run waits for an answer
    /// that cannot come.
    ///
    /// - Parameters:
    ///   - operation: The event of the question.
    ///   - session: The session of the run.
    func answerQuestion(of operation: OperationEvent, on session: any RoutedSession) async {
        guard let question = operation.elicitation else {
            return
        }
        await session.respond(
            elicitationId: question.elicitationId.ulidString,
            response: .cancel(reason: RunPlane.noUserPresentReason))
    }

    /// Gives the signal of one session event, or `nil` for an event that
    /// decides nothing.
    ///
    /// - The end of an answer gives ``AgentRunSignal/limitHit(partial:)``
    ///   after the count went above the limit. Else an answer gives
    ///   ``AgentRunSignal/idle(_:acceptedMessages:)`` when the session is
    ///   idle.
    /// - A run event of a child, a terminal event of a mail with no answer,
    ///   and the close record of a tool call give
    ///   ``AgentRunSignal/idle(_:acceptedMessages:)`` when the session is
    ///   idle after them (``idleSignalAfterRunEvent(on:)``).
    /// - A failed answer to mail alone gives
    ///   ``AgentRunSignal/mailAnswerFailed(_:)``. A failed answer of the task
    ///   prompt or of a message from the caller gives nothing here: the wait
    ///   for its id gives its error.
    /// - A hold of the mail gives ``AgentRunSignal/mailDeliveryPaused(_:)``.
    ///   While the hold is in force, a run event of a child and the close
    ///   record of a tool call give ``AgentRunSignal/pauseDrained``, not an
    ///   idle check: the held mail has no terminal event, thus the session is
    ///   not idle.
    ///
    /// - Parameters:
    ///   - event: The event, already recorded.
    ///   - session: The session of the run.
    /// - Returns: The signal, or `nil`.
    private func signal(after event: SessionEvent, on session: any RoutedSession) async -> AgentRunSignal? {
        switch event {
        case .answered(let answer):
            if turns.isLimitHit {
                return .limitHit(partial: answer.reply)
            }
            return await idleSignal(reply: answer.reply, on: session)
        case .runSettled, .runMessage, .cancelled, .lost, .elicitationEnded, .elicitationCompleted:
            return await signalAfterRunEvent(on: session)
        case .toolInvocation(let record, _) where record.closedAt != nil:
            return await signalAfterRunEvent(on: session)
        case .answerFailed(let failure):
            if turns.isLimitHit {
                return .limitHit(partial: answers.partial)
            }
            return isAnswerToMailAlone(failure.mailIds) ? .mailAnswerFailed(failure.reason) : nil
        case .mailDeliveryPaused(let pause):
            return .mailDeliveryPaused(pause.description)
        default:
            return nil
        }
    }

    /// Gives the signal after a run event of a child or the close record of a
    /// tool call: ``AgentRunSignal/pauseDrained`` while the Router holds the
    /// mail, else the idle signal (``idleSignalAfterRunEvent(on:)``).
    ///
    /// - Parameter session: The session of the run.
    /// - Returns: The signal, or `nil`.
    private func signalAfterRunEvent(on session: any RoutedSession) async -> AgentRunSignal? {
        guard pauseDescription == nil else {
            return .pauseDrained
        }
        return await idleSignalAfterRunEvent(on: session)
    }

    /// Gives ``AgentRunSignal/idle(_:acceptedMessages:)`` when the session is
    /// idle after an event that is not the end of an answer, with the reply
    /// of the last answer.
    ///
    /// The answer to the mail of a child can end before the output of the
    /// run event that the mail holds. A tool call can close after the answer
    /// that started it ended. The idle check of that answer then fails, and
    /// this check after the later event is the one that ends the run.
    ///
    /// - Parameter session: The session of the run.
    /// - Returns: The signal, or `nil` when no answer ended yet, when an
    ///   answer is open, when the count of passes is above the limit, or when
    ///   the session is not idle.
    private func idleSignalAfterRunEvent(on session: any RoutedSession) async -> AgentRunSignal? {
        let answers = answers
        guard answers.hasAnswered, !answers.isAnswerOpen, !turns.isLimitHit else {
            return nil
        }
        return await idleSignal(reply: answers.lastReply, on: session)
    }

    /// Gives ``AgentRunSignal/idle(_:acceptedMessages:)`` with `reply` when
    /// the session is idle (``acceptedMessagesIfIdle(on:)``).
    ///
    /// A run that recorded its final state makes no idle check
    /// (``isSettled``). The follower reads the events of the session until
    /// the close of the session, and the close sends events too, for example
    /// the `cancelled` event of each queued mail. A check at that time can
    /// change nothing.
    ///
    /// - Parameters:
    ///   - reply: The reply of the last answer.
    ///   - session: The session of the run.
    /// - Returns: The signal, or `nil` when the run recorded its final state
    ///   or when the session is not idle.
    private func idleSignal(reply: String, on session: any RoutedSession) async -> AgentRunSignal? {
        guard !isSettled, let acceptedMessages = await acceptedMessagesIfIdle(on: session) else {
            return nil
        }
        return .idle(reply, acceptedMessages: acceptedMessages)
    }

    /// Tells if the session of the run is idle after an event, and gives the
    /// count of accepted messages from the caller for an idle session.
    ///
    /// The rule goes by mail id and by the completion token of each tool
    /// call. It reads no text of a prompt and no transcript. The session is
    /// idle when all of these are true:
    ///
    /// - No answer is open.
    /// - No message from the caller is on its way to the mail queue
    ///   (``acceptedMessagesWhenNoneInbound``).
    /// - Each run that this run started ended.
    /// - No user-type mail waits in the queue (``userTypeKinds``), and the
    ///   pump runs no mail. Run mail in the queue does not keep the session
    ///   from idle: progress mail starts no answer, thus it can wait after
    ///   the last answer.
    /// - Each tool call of the session closed
    ///   (``ParentSessionWatch/isEachCallClosed``). A call posts its open
    ///   record before it gives the model the pending envelope of a
    ///   background run, and the body of a `start agent` call adds its run
    ///   to ``children`` later. Thus the open record keeps the session from
    ///   idle also while the run is not in ``children``.
    /// - No question of the session is open (`openElicitationIds()`), also a
    ///   question that a child sent up through this session. An answer or an
    ///   end of the question gives a new idle check
    ///   (``signal(after:on:)``).
    /// - Each mail of the run events of the call of each child, and each
    ///   user-type mail of the run (``mailedUserTypeMail``), has a terminal
    ///   event (``ParentSessionWatch/hasTerminal(forEachMailOfCalls:and:)``).
    ///   The output of each run event of a call comes before the close record
    ///   of that call, thus the watch knows each mail of a closed call. The
    ///   mail of a run that ended in its call, for example the terminal of a
    ///   synchronous tool that posted progress, does not count: it starts no
    ///   answer, thus no terminal event can come for it while the session is
    ///   idle.
    ///
    /// A message from the caller keeps the session from idle from the time
    /// that ``deliver(_:from:)`` accepts it to its terminal event. While the
    /// run holds the message, and while the message goes to the queue,
    /// ``acceptedMessagesWhenNoneInbound`` is `nil`. After that time, the id
    /// of the message is in ``mailedUserTypeMail`` and has no terminal event
    /// until its answer ends. The check gives the count of accepted messages
    /// that it read first. A message that the run accepts after that read
    /// changes the count, and the run does not end on this check
    /// (``settle(idle:acceptedMessages:)``).
    ///
    /// - Parameter session: The session of the run.
    /// - Returns: The count of accepted messages when the session is idle, or
    ///   `nil` when it is not idle.
    private func acceptedMessagesIfIdle(on session: any RoutedSession) async -> Int? {
        await idleHooks.beforeIdleCheck()
        guard !answers.isAnswerOpen,
            let acceptedMessages = acceptedMessagesWhenNoneInbound,
            children.runs.allSatisfy({ $0.state != .running })
        else {
            return nil
        }
        let depth = await session.mailQueueDepth()
        guard Self.userTypeKinds.allSatisfy({ (depth.depthByKind[$0] ?? 0) == 0 }), depth.running.isEmpty else {
            return nil
        }
        guard sessionWatch.isEachCallClosed,
            sessionWatch.hasTerminal(
                forEachMailOfCalls: children.runs.compactMap { $0.context?.completionToken },
                and: mailedUserTypeMail.map(\.id)),
            await session.openElicitationIds().isEmpty
        else {
            return nil
        }
        return acceptedMessages
    }

    /// The kinds of mail that keep the session from idle while they wait in
    /// the queue: each kind except run mail.
    static let userTypeKinds: [MailKind] = MailKind.allCases.filter { $0 != .runEvent }
}
