---
assignees:
- claude-code
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
- 01M376DZSHS7M9CD50Z24X1ZBZ
position_column: todo
position_ordinal: '8480'
title: AgentFrontmatter.decode with the colon retry
---
## What
Layer 1, part 1 (plan.md §4.2, §4.3 step 1). Decode the raw frontmatter of one agent file.

- Create `Sources/FoundationModelsAgents/Definition/AgentFrontmatter.swift`:
  - `public struct AgentFrontmatter: Sendable, Equatable` with the tier 1 fields as raw values (`name`, `description`, `tools`, `disallowedTools`, `model`, `skills`, `maxTurns`, `compactionPrompt`, `disableModelInvocation`, `userInvocable`), the tier 2 fields (`color`, `background`), the tier 3 keys that are present, the unknown keys (`[String: String]` or a YAML-value map), and `notes: [String]` (decode notes).
  - `tools`, `disallowedTools`, and `skills` accept a comma-separated string or a YAML list.
  - `public static func decode(_ yaml: String) -> AgentFrontmatter?` with the signature that `FrontmatterDocumentStack(decode:)` needs. It uses Yams and never throws.
  - On a Yams failure, retry one time with the Skills rule: quote a `description:` value that holds an unquoted `:`. Look at `../FoundationModelsSkills/Sources/FoundationModelsSkills/Frontmatter/FrontmatterDecoder.swift`. A retry that succeeds adds a note.
- The frontmatter is never rendered: `{{ x }}` in a value stays text.

## Acceptance Criteria
- [ ] The fixture `defaults/agents/code-reviewer.md` frontmatter decodes to the expected values.
- [ ] `broken/agents/bad-colon-description.md` decodes after the retry and has one note.
- [ ] Invalid YAML after the retry gives `nil`.
- [ ] `tools: Read, Grep` and `tools: [Read, Grep]` give the same list; `Agent(a, b)` stays one entry.
- [ ] Unknown keys and tier 3 keys are kept for diagnostics.

## Tests
- [ ] `Tests/FoundationModelsAgentsTests/AgentFrontmatterTests.swift` covers each criterion and `{{ x }}` staying text.
- [ ] Run `swift test --filter AgentFrontmatterTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.