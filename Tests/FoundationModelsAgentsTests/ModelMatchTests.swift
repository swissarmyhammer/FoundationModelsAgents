@testable import FoundationModelsAgents
import FoundationModelsRouter
import Testing

/// Pins the model match table of plan.md §7 against the scripted profile.
///
/// Each row resolves its own profile. The `standard` slot of the profile has
/// the model `scripted/standard`. The `flash` slot has the pinned model
/// `scripted/flash@rev1`, thus a row can match the full reference or the part
/// before `@`.
@Suite("Model match")
struct ModelMatchTests {
    /// One `model` value, the slot of the caller, and the result.
    struct Row: Sendable, CustomTestStringConvertible {
        /// The `model` value of the agent, or `nil` when the key is absent.
        let model: String?

        /// The slot of the caller.
        let inherited: ModelSlot

        /// The slot that the match must give.
        let expected: ModelSlot

        /// `true` when the match must give a warning.
        let warns: Bool

        /// The value and the slot of the caller, as the name of the case.
        var testDescription: String {
            "`\(model ?? "absent")` with the caller on `\(inherited.rawValue)`"
        }
    }

    /// The revision of the pinned `flash` model.
    static let flashRevision = "rev1"

    /// The revision of the pinned `standard` model of the shared-repository
    /// case. It is not ``flashRevision``.
    static let standardRevision = "rev0"

    /// The pinned `flash` model: `scripted/flash@rev1`.
    static let pinnedFlashModel = ModelRef(
        stringLiteral: "\(ScriptedProfile.flashModel.stringValue)@\(flashRevision)")

    /// The rows of the §7 table.
    static let tableRows: [Row] = [
        Row(model: nil, inherited: .flash, expected: .flash, warns: false),
        Row(model: nil, inherited: .standard, expected: .standard, warns: false),
        Row(model: "inherit", inherited: .flash, expected: .flash, warns: false),
        Row(model: "inherit", inherited: .standard, expected: .standard, warns: false),
        Row(model: "standard", inherited: .flash, expected: .standard, warns: false),
        Row(model: "flash", inherited: .standard, expected: .flash, warns: false),
        Row(model: "scripted/standard", inherited: .flash, expected: .standard, warns: false),
        Row(model: "scripted/flash@rev1", inherited: .standard, expected: .flash, warns: false),
        Row(model: "scripted/flash", inherited: .standard, expected: .flash, warns: false),
        Row(model: "opus", inherited: .standard, expected: .standard, warns: true),
        Row(model: "sonnet", inherited: .flash, expected: .flash, warns: true),
        Row(model: "embedding", inherited: .flash, expected: .flash, warns: true),
        Row(model: "scripted/embedding", inherited: .standard, expected: .standard, warns: true),
        Row(model: "scripted/flash@other", inherited: .standard, expected: .standard, warns: true),
        Row(model: "no-such-model", inherited: .flash, expected: .flash, warns: true)
    ]

    /// The rows that spell a value in a different case. Slot names and
    /// Hugging Face repository ids do not use the case.
    static let caseRows: [Row] = [
        Row(model: "INHERIT", inherited: .flash, expected: .flash, warns: false),
        Row(model: "Flash", inherited: .standard, expected: .flash, warns: false),
        Row(model: "Scripted/Standard", inherited: .flash, expected: .standard, warns: false)
    ]

    /// Resolves the profile of the table rows.
    ///
    /// - Returns: A profile whose `flash` model is ``pinnedFlashModel``.
    /// - Throws: Whatever `ScriptedProfile.make` throws.
    static func makeTableProfile() async throws -> LanguageModelProfile {
        let (_, profile) = try await ScriptedProfile.make(
            script: ScriptedAgentScript([]), flash: pinnedFlashModel)
        return profile
    }

    /// Each row of the §7 table gives the stated slot, and a warning only
    /// for a value that matches nothing.
    @Test("Each row of the table gives the stated slot", arguments: tableRows + caseRows)
    func rowGivesStatedSlot(_ row: Row) async throws {
        let profile = try await Self.makeTableProfile()

        let result = ModelMatch.match(row.model, profile: profile, inherited: row.inherited)

        #expect(result.slot == row.expected)
        #expect((result.warning != nil) == row.warns)
    }

    /// A repository that the two slots share, each slot at its own revision,
    /// gives `standard`. The full reference of each slot gives that slot.
    ///
    /// The Router gives the two slots two different models, thus the slots
    /// can share a repository but not a full reference.
    @Test("A shared repository gives standard", arguments: [ModelSlot.flash, .standard])
    func sharedRepositoryGivesStandard(_ inherited: ModelSlot) async throws {
        let repository = ScriptedProfile.standardModel.stringValue
        let standardModel = ModelRef(stringLiteral: "\(repository)@\(Self.standardRevision)")
        let flashModel = ModelRef(stringLiteral: "\(repository)@\(Self.flashRevision)")
        let (_, profile) = try await ScriptedProfile.make(
            script: ScriptedAgentScript([]), standard: standardModel, flash: flashModel)

        let shared = ModelMatch.match(repository, profile: profile, inherited: inherited)
        let flash = ModelMatch.match(flashModel.stringValue, profile: profile, inherited: inherited)

        #expect(shared.slot == .standard)
        #expect(shared.warning == nil)
        #expect(flash.slot == .flash)
        #expect(flash.warning == nil)
    }

    /// `model: sonnet` gives a warning that names the value, the profile,
    /// and the slot that the run uses, and then gives the inherited slot.
    @Test("model: sonnet gives a warning and the inherited slot")
    func sonnetGivesWarningAndInheritedSlot() async throws {
        let profile = try await Self.makeTableProfile()

        let result = ModelMatch.match("sonnet", profile: profile, inherited: .flash)
        let warning = try #require(result.warning)

        #expect(result.slot == .flash)
        #expect(warning.contains("`sonnet`"))
        #expect(warning.contains("`\(profile.definitionName)`"))
        #expect(warning.contains("`flash` slot"))
        #expect(warning.contains("`\(Self.pinnedFlashModel.stringValue)`"))
        #expect(warning.contains("`\(ScriptedProfile.standardModel.stringValue)`"))
    }
}
