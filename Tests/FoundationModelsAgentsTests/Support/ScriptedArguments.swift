import Synchronization

/// The arguments of a scripted tool call that the test sets after it makes
/// the script.
///
/// A ``ScriptedAgentStep/deferredToolCall(name:arguments:)`` step reads the
/// arguments when the model reaches the step. Thus a test can give a tool
/// call a value that exists only at run time, for example the id of a run.
///
/// A class, because the script and the test hold the same arguments. A
/// `Mutex` guards the text, thus the `Sendable` conformance is
/// compiler-checked.
final class ScriptedArguments: Sendable {
    /// The JSON text of the arguments.
    private let text: Mutex<String>

    /// Makes the arguments with a first text.
    ///
    /// - Parameter json: The JSON text of the arguments until the test sets
    ///   a new text. The default is an empty JSON object.
    init(_ json: String = "{}") {
        self.text = Mutex(json)
    }

    /// The JSON text of the arguments.
    var json: String {
        text.withLock { $0 }
    }

    /// Sets the JSON text of the arguments.
    ///
    /// - Parameter json: The new JSON text.
    func set(_ json: String) {
        text.withLock { $0 = json }
    }
}
