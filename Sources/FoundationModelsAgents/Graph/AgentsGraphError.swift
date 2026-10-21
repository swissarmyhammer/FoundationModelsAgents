import FoundationModelsExtras

/// A call that the `agents` GraphQL endpoint refuses (AG-8).
///
/// The endpoint gives each case in the `errors` list of a response, with its
/// ``code`` in `extensions.code`. The ``message`` tells how to correct the
/// call. An id that no agent has is not an error: `agent(id:)` gives `null`.
public enum AgentsGraphError: CodedError, Equatable, CaseIterable {
    /// `CATALOG_NOT_LOADED`: the host did not load the registry yet, thus the
    /// registry read no file. An empty list would tell that the folder has no
    /// agent, which is not known yet.
    case catalogNotLoaded

    /// Each code that the endpoint gives of its own: the code of each case,
    /// in the order of the cases. The endpoint gives no warning code. This
    /// is the one list of the codes of the endpoint, for the code check of
    /// the conventions (EXTRAS-9 rule 8, EXTRAS-11).
    public static var codes: [String] {
        allCases.map(\.code)
    }

    /// The code of the error, for example `CATALOG_NOT_LOADED`.
    public var code: String {
        switch self {
        case .catalogNotLoaded: "CATALOG_NOT_LOADED"
        }
    }

    /// The message of the error: what is wrong, and how to correct the call.
    public var message: String {
        switch self {
        case .catalogNotLoaded:
            "The agent catalog of the session folder is not loaded yet. Send the query again after the host "
                + "loads the agent registry."
        }
    }
}
