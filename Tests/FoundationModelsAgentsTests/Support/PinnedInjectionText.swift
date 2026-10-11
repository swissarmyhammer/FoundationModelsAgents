/// The injection sentences of the `agents` tool, word for word.
///
/// The pending text of `start agent` and the description of the tool both
/// hold these sentences. The tests of the two texts pin them from this one
/// constant, thus the two pins cannot drift apart.
enum PinnedInjectionText {
    /// The sentences that tell the model that the session injects the result
    /// as a new message, not to wait or to check, and to do nothing when no
    /// other work can be done.
    static let sentences = """
        When the work finishes, the session injects its result into this conversation as a new message. \
        That message starts you working again, so you do not need to wait, to check, or to ask for it. \
        Do not call a tool to wait or to check. If you have other work that does not need this result, \
        do that work now. If no other work can be done until the result comes back, do nothing: write no \
        text and call no tool. When the injected result arrives, continue the task from it.
        """
}
