import FoundationModelsExtras

/// A sink that drops each event. A test uses it for a `ToolContext` whose events it does not read.
struct DroppingSink: OperationEventSink {
    /// Drops the event.
    ///
    /// - Parameter event: The event.
    func post(event: OperationEvent) async {}
}
