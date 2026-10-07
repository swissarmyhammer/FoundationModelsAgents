@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

extension NestedRunTests {
    /// Pins the messages that a running child sends to its parent run with
    /// `send caller` (plan.md §9.1, §9.2): the Router gives each message to
    /// the parent as mail, the parent answers each message before it ends,
    /// `check agent` on the parent tells the last message of the child, and
    /// mail that reaches `mailOnlyAnswerLimit` ends the parent with the
    /// paused outcome.
    ///
    /// The parent runs on the `standard` slot, and the child on the `flash`
    /// slot. A slot has one generation queue, and a run that waits on a gate
    /// holds the queue of its slot. Thus one run can answer while the other
    /// waits.
    @Suite("Messages from a child")
    struct Messages {
        /// The agent of the temporary layer that starts the child.
        private static let parent = "message-parent"

        /// The agent of the temporary layer on the `flash` slot. Its `Agent`
        /// key gives it the agents tool, thus it can call `send caller`.
        private static let messenger = "messenger"

        /// The agent files of the temporary layer, by path.
        private static let agentFiles = [
            "agents/\(parent).md": """
                ---
                name: \(parent)
                description: Gives a part of a task to the messenger.
                tools: Agent
                ---

                You are a parent.
                """,
            "agents/\(messenger).md": """
                ---
                name: \(messenger)
                description: Does a part of a task, and tells its caller about it.
                model: flash
                tools: Agent
                ---

                You are a messenger.
                """
        ]

        /// The task prompt of the parent. It is also the key of its play.
        private static let parentKey = "messages-parent-key: divide the task"

        /// The prompt of the child. It is also the key of its play.
        private static let childKey = "messages-child-key: do the part"

        /// The final text of the child.
        private static let childText = "The part is done."

        /// The first message of the child.
        private static let firstMessage = "messages-first: half of the part is done"

        /// The second message of the child.
        private static let secondMessage = "messages-second: the part is almost done"

        /// The count of answers to mail in the play of the parent. Each test
        /// needs this count or fewer.
        private static let mailAnswerCount = 3

        /// The `mailOnlyAnswerLimit` of the session of the parent in the
        /// paused test: one answer that mail alone starts.
        private static let pausedLimit = 1

        /// The steps of the parent: start the child, end the task answer
        /// with ``NestedRunTests/startedText``, then answer each mail with the
        /// text of its prompt.
        ///
        /// - Parameters:
        ///   - taskGate: Holds the task answer after the `start agent` call,
        ///     or `nil`.
        ///   - mailGate: Holds the first answer to mail before its reply, or
        ///     `nil`.
        /// - Returns: The play of the parent.
        private static func parentPlay(
            holdingTaskAt taskGate: ScriptedGate? = nil, holdingMailAt mailGate: ScriptedGate? = nil
        ) -> ScriptedAgentPlay {
            let task = [NestedRunTests.startStep(messenger, prompt: childKey)] + (taskGate.map { [.wait($0)] } ?? [])
            let mail = (mailGate.map { [.wait($0)] } ?? [])
                + [ScriptedAgentStep](repeating: .finalTextOfLastPrompt, count: mailAnswerCount)
            return ScriptedAgentPlay(key: parentKey, steps: task + [.finalText(NestedRunTests.startedText)] + mail)
        }

        /// A step of the child that sends `message` to its caller.
        ///
        /// - Parameter message: The text of the message.
        /// - Returns: The step.
        private static func send(_ message: String) -> ScriptedAgentStep {
            .agentsToolCall(AgentsToolArguments.sendCaller(message: message))
        }

        /// Makes the layer and the harness, starts the parent, and gives it
        /// to `body`. Then it deletes the harness and the layer.
        ///
        /// - Parameters:
        ///   - parentPlay: The play of the parent.
        ///   - childSteps: The steps of the child.
        ///   - mailOnlyAnswerLimit: The limit of answers that mail alone
        ///     starts in the session of each run.
        ///   - body: Reads the parent and the script.
        /// - Returns: The value of `body`.
        /// - Throws: The error of the harness, of the start, or of `body`.
        private static func withParent<Value>(
            parentPlay: ScriptedAgentPlay = parentPlay(), childSteps: [ScriptedAgentStep],
            mailOnlyAnswerLimit: Int = SessionConfiguration.defaultMailOnlyAnswerLimit,
            body: (AgentRun, ScriptedAgentScript) async throws -> Value
        ) async throws -> Value {
            let layer = try TemporaryLayer.make(holding: agentFiles)
            defer { try? layer.delete() }
            let script = ScriptedAgentScript([parentPlay, ScriptedAgentPlay(key: childKey, steps: childSteps)])
            let harness = try await AgentRunHarness.make(script: script, registry: AgentRegistry(layers: [layer.layer]))
            defer { try? harness.delete() }
            let parent = try await harness.makeRunner(mailOnlyAnswerLimit: mailOnlyAnswerLimit)
                .start(Self.parent, prompt: parentKey)
            return try await body(parent, script)
        }

        /// Waits until `parent` started its child, and gives the child.
        ///
        /// - Parameter parent: The parent run.
        /// - Returns: The child.
        /// - Throws: `CancellationError` when the test is cancelled.
        private static func child(of parent: AgentRun) async throws -> AgentRun {
            while true {
                if let child = parent.children.runs.first {
                    return child
                }
                try await Task.sleep(for: NestedRunTests.pollInterval)
            }
        }

        /// Gives the line that the Router puts in a prompt for the mail of
        /// `message` from `child`.
        ///
        /// - Parameters:
        ///   - message: The text of the message.
        ///   - child: The child that sent it.
        /// - Returns: The mail line.
        /// - Throws: The error of `#require` when the child has no context.
        private static func mailLine(_ message: String, of child: AgentRun) throws -> String {
            let context = try #require(child.context)
            return ParentSessionWatch.mailLine(
                of: OperationEvent(
                    tool: context.tool, op: context.op, correlationID: context.completionToken, kind: .message,
                    detail: message))
        }

        /// Gives the position of the first prompt that holds `text`.
        ///
        /// - Parameters:
        ///   - text: The text that the prompt holds.
        ///   - script: The script that recorded the prompts.
        /// - Returns: The position.
        /// - Throws: The error of `#require` when no prompt holds `text`.
        private static func position(ofPromptHolding text: String, in script: ScriptedAgentScript) throws -> Int {
            try #require(script.prompts.firstIndex { $0.contains(text) })
        }

        /// Waits until the report of `parent` tells `message` as the last
        /// event of a child, and gives the report.
        ///
        /// - Parameters:
        ///   - message: The text of the message.
        ///   - parent: The parent run.
        /// - Returns: The report.
        /// - Throws: `CancellationError` when the test is cancelled.
        private static func report(telling message: String, of parent: AgentRun) async throws -> String {
            while !parent.report.contains("message: \(message)") {
                try await Task.sleep(for: NestedRunTests.pollInterval)
            }
            return parent.report
        }

        /// Waits until `parent` waits for its child after an answer.
        ///
        /// - Parameter parent: The parent run.
        /// - Throws: `CancellationError` when the test is cancelled.
        private static func waitingPhase(of parent: AgentRun) async throws {
            while parent.phase != .waitingForChildren {
                try await Task.sleep(for: NestedRunTests.pollInterval)
            }
        }

        /// `true` when `state` failed because the Router paused the mail.
        ///
        /// - Parameter state: The final state of a run.
        /// - Returns: `true` for that failure.
        private static func isPaused(_ state: AgentRunState) -> Bool {
            if case .failed(.mailDeliveryPaused) = state { return true }
            return false
        }

        @Test(
            "a child that sends a message and ends at once: the parent answers the message and the final message, then ends",
            .timeLimit(.minutes(1)))
        func messageThenEndAtOnce() async throws {
            try await Self.withParent(childSteps: [Self.send(Self.firstMessage), .finalText(Self.childText)]) {
                parent, script in
                let result = try await parent.result()
                let child = try await Self.child(of: parent)
                let message = try Self.position(ofPromptHolding: Self.mailLine(Self.firstMessage, of: child), in: script)
                let final = try Self.position(ofPromptHolding: child.report, in: script)

                #expect(child.state == .finished(Self.childText))
                #expect(message <= final)
                #expect(result == script.prompts.last)
            }
        }

        @Test("a child that sends two messages: the parent answers both before it ends", .timeLimit(.minutes(1)))
        func twoMessagesAreAnswered() async throws {
            let childSteps = [Self.send(Self.firstMessage), Self.send(Self.secondMessage), .finalText(Self.childText)]
            try await Self.withParent(childSteps: childSteps) { parent, script in
                let result = try await parent.result()
                let child = try await Self.child(of: parent)
                let first = try Self.position(ofPromptHolding: Self.mailLine(Self.firstMessage, of: child), in: script)
                let second = try Self.position(ofPromptHolding: Self.mailLine(Self.secondMessage, of: child), in: script)
                let final = try Self.position(ofPromptHolding: child.report, in: script)

                #expect(first <= second)
                #expect(second <= final)
                #expect(result == script.prompts.last)
            }
        }

        @Test(
            "a message in the task turn of the parent waits until that answer ends, and the parent then answers it",
            .timeLimit(.minutes(1)))
        func messageInTaskTurnWaitsForTheAnswer() async throws {
            let taskGate = ScriptedGate()
            let mailGate = ScriptedGate()
            let childGate = ScriptedGate()
            try await Self.withParent(
                parentPlay: Self.parentPlay(holdingTaskAt: taskGate, holdingMailAt: mailGate),
                childSteps: [Self.send(Self.firstMessage), .wait(childGate), .finalText(Self.childText)]
            ) { parent, script in
                _ = try await Self.report(telling: Self.firstMessage, of: parent)
                let child = try await Self.child(of: parent)
                let line = try Self.mailLine(Self.firstMessage, of: child)
                let heldInTaskTurn = script.prompts.contains { $0.contains(line) }
                taskGate.open()
                await mailGate.waitForArrival()
                let phaseInMailAnswer = parent.phase
                let mailPrompt = script.prompts.last
                mailGate.open()
                childGate.open()
                let result = try await parent.result()

                #expect(!heldInTaskTurn)
                #expect(phaseInMailAnswer == .answeringMail)
                #expect(mailPrompt?.contains(line) == true)
                #expect(
                    try Self.position(ofPromptHolding: line, in: script)
                        > Self.position(ofPromptHolding: Self.parentKey, in: script))
                #expect(result.contains(child.report))
                #expect(result == script.prompts.last)
            }
        }

        @Test(
            "message mail and the final message in two submissions: check agent tells the message while the child runs",
            .timeLimit(.minutes(1)))
        func messageAndFinalMessageInTwoSubmissions() async throws {
            let childGate = ScriptedGate()
            try await Self.withParent(
                childSteps: [Self.send(Self.firstMessage), .wait(childGate), .finalText(Self.childText)]
            ) { parent, script in
                let child = try await Self.child(of: parent)
                let line = try Self.mailLine(Self.firstMessage, of: child)
                try await NestedRunTests.arrival(ofPromptContaining: line, in: script)
                try await Self.waitingPhase(of: parent)
                let report = try await Self.report(telling: Self.firstMessage, of: parent)
                let token = try #require(child.context?.completionToken)
                childGate.open()
                let result = try await parent.result()
                let message = try Self.position(ofPromptHolding: line, in: script)
                let final = try Self.position(ofPromptHolding: child.report, in: script)

                #expect(report.hasPrefix("\(parent.subject) is running."))
                #expect(report.contains("\nLast event of \(token): message: \(Self.firstMessage)\n"))
                #expect(!script.prompts[message].contains(child.report))
                #expect(message < final)
                #expect(result == script.prompts.last)
            }
        }

        @Test(
            "message mail and the final message in one submission: one prompt holds both, and the parent then ends",
            .timeLimit(.minutes(1)))
        func messageAndFinalMessageInOneSubmission() async throws {
            let taskGate = ScriptedGate()
            try await Self.withParent(
                parentPlay: Self.parentPlay(holdingTaskAt: taskGate),
                childSteps: [Self.send(Self.firstMessage), .finalText(Self.childText)]
            ) { parent, script in
                let child = try await Self.child(of: parent)
                let token = try #require(child.context?.completionToken)
                while parent.sessionWatch.detail(ofSettledCall: token) == nil {
                    try await Task.sleep(for: NestedRunTests.pollInterval)
                }
                taskGate.open()
                let result = try await parent.result()
                let line = try Self.mailLine(Self.firstMessage, of: child)

                #expect(script.prompts.contains { $0.contains(line) && $0.contains(child.report) })
                #expect(result == script.prompts.last)
            }
        }

        @Test(
            "message mail above mailOnlyAnswerLimit ends the parent with the paused outcome, and it does not hang",
            .timeLimit(.minutes(1)))
        func messagesAboveTheLimitPauseTheParent() async throws {
            let childGate = ScriptedGate()
            try await Self.withParent(
                childSteps: [
                    Self.send(Self.firstMessage), .wait(childGate), Self.send(Self.secondMessage),
                    .finalText(Self.childText)
                ],
                mailOnlyAnswerLimit: Self.pausedLimit
            ) { parent, script in
                let child = try await Self.child(of: parent)
                try await NestedRunTests.arrival(
                    ofPromptContaining: Self.mailLine(Self.firstMessage, of: child), in: script)
                childGate.open()
                let final = await parent.finalState()
                let secondLine = try Self.mailLine(Self.secondMessage, of: child)

                #expect(Self.isPaused(final))
                #expect(!script.prompts.contains { $0.contains(secondLine) })
            }
        }
    }
}
