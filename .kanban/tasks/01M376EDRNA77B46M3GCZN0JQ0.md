---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
title: 'S1 (FoundationModelsSkills): the agent: key on SkillListing'
---
## What
A change in the sibling repository `../FoundationModelsSkills`, not in this package (plan.md §9.4, §14 S1). Push it to `main` of that repository, because this package uses it as a remote dependency.

- In `../FoundationModelsSkills/Sources/FoundationModelsSkills/Frontmatter/` decode an optional `agent:` string key.
- In `../FoundationModelsSkills/Sources/FoundationModelsSkills/Listing/SkillListing.swift` add `public var agent: String?`.
- In `../FoundationModelsSkills/Sources/FoundationModelsSkills/Registry/SkillsRegistry+SlashCommands.swift` leave out of `commands(workingDirectory:)` each skill whose `agent` is not `nil`, so one name has one provider.
- `use skill` and `SkillsRegistry.call(id:arguments:)` do not change for such a skill.
- Update the Skills README or docs where they list the frontmatter keys.

## Acceptance Criteria
- [ ] A skill with `agent: code-reviewer` has `SkillListing.agent == "code-reviewer"`.
- [ ] That skill is not in `commands(workingDirectory:)`; a skill with no `agent:` still is.
- [ ] `use skill` on that skill gives the same rendered text as before.
- [ ] The full Skills test suite passes.

## Tests
- [ ] Add cases to `../FoundationModelsSkills/Tests/FoundationModelsSkillsTests/SkillListingTests.swift`, `SlashCommandProvidingTests.swift`, and `UseSkillPlainTextTests.swift`.
- [ ] Run `swift test` in `../FoundationModelsSkills`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.