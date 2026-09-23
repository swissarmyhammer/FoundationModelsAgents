import FoundationModelsRouter

/// Matches the `model` value of an agent to a generation slot of the
/// profile (plan.md §7).
///
/// | `model:` | Result |
/// |---|---|
/// | absent or `inherit` | the slot of the caller |
/// | `standard` or `flash` | that slot |
/// | `chosen.stringValue` of a slot, or its part before `@` | that slot |
/// | other (`opus`, `sonnet`, `embedding`, unknown) | a warning, the caller slot |
///
/// When the two slots share a model, its reference gives `standard`.
///
/// Slot names and Hugging Face repository ids do not use the case, thus the
/// match does not use the case.
enum ModelMatch {
    /// One generation slot and the key path to its model in the profile.
    struct GenerationSlot: Sendable {
        /// The slot.
        let slot: ModelSlot

        /// The model of the slot in the profile.
        let model: KeyPath<LanguageModelProfile, RoutedLLM> & Sendable
    }

    /// The `model` value that asks for the slot of the caller.
    static let inheritValue = "inherit"

    /// The separator between the repository and the revision of a model
    /// reference.
    static let revisionSeparator: Character = "@"

    /// The slots that a `model` value can select, in match order.
    ///
    /// `standard` is first, thus a model that the two slots share gives
    /// `standard`. The `embedding` slot makes no session, thus it is not in
    /// the list.
    static let generationSlots = [
        GenerationSlot(slot: .standard, model: \.standard),
        GenerationSlot(slot: .flash, model: \.flash)
    ]

    /// Gives the slot for the `model` value of an agent.
    ///
    /// - Parameters:
    ///   - model: The `model` value of the agent, or `nil` when the key is
    ///     absent.
    ///   - profile: The resolved profile of the runner.
    ///   - inherited: The slot of the caller. For a host-started run, it is
    ///     `AgentEnvironment.defaultSlot`.
    /// - Returns: The slot, and a warning when `model` matches nothing. The
    ///   slot is then `inherited`.
    static func match(
        _ model: String?, profile: LanguageModelProfile, inherited: ModelSlot
    ) -> (slot: ModelSlot, warning: String?) {
        guard let model else { return (inherited, nil) }
        let key = model.lowercased()
        guard key != inheritValue else { return (inherited, nil) }
        let matched = generationSlots.first { $0.slot.rawValue == key }
            ?? generationSlots.first { references(of: $0, in: profile).contains(key) }
        guard let matched else {
            return (inherited, warning(model: model, profile: profile, inherited: inherited))
        }
        return (matched.slot, nil)
    }

    /// Gives the model of the generation slot `slot` in `profile`.
    ///
    /// - Parameters:
    ///   - slot: The slot of a match: `.standard` or `.flash`.
    ///   - profile: The resolved profile.
    /// - Returns: The model of the slot in ``generationSlots``. A slot that is
    ///   not in the list gives the model of the first slot, `standard`.
    static func model(of slot: ModelSlot, in profile: LanguageModelProfile) -> RoutedLLM {
        let generationSlot = generationSlots.first { $0.slot == slot } ?? generationSlots[0]
        return profile[keyPath: generationSlot.model]
    }

    /// Gives the values that name the model of a slot: the full reference
    /// and the part before `@`, in lower case.
    ///
    /// - Parameters:
    ///   - generationSlot: The slot.
    ///   - profile: The resolved profile.
    /// - Returns: The full reference and the repository id.
    static func references(
        of generationSlot: GenerationSlot, in profile: LanguageModelProfile
    ) -> Set<String> {
        let reference = profile[keyPath: generationSlot.model].chosen.stringValue.lowercased()
        return [reference, String(reference.prefix { $0 != revisionSeparator })]
    }

    /// Makes the warning for a `model` value that matches nothing.
    ///
    /// The warning names the values that match, thus the author can correct
    /// the file.
    ///
    /// - Parameters:
    ///   - model: The `model` value of the agent.
    ///   - profile: The resolved profile.
    ///   - inherited: The slot that the run uses.
    /// - Returns: The warning text.
    static func warning(model: String, profile: LanguageModelProfile, inherited: ModelSlot) -> String {
        let names = [inheritValue] + generationSlots.map(\.slot.rawValue)
            + generationSlots.map { profile[keyPath: $0.model].chosen.stringValue }
        let valid = names.lazy.map { "`\($0)`" }.joined(separator: ", ")
        return "The model `\(model)` is not a slot or a model of the profile "
            + "`\(profile.definitionName)`. The run uses the `\(inherited.rawValue)` slot. "
            + "Use one of these values: \(valid)."
    }
}
