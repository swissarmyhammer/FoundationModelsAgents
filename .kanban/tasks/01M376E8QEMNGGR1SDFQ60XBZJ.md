---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m37bmkct8skgre9sz3dfxjy4
  text: |-
    Research:
    - `FrontmatterDocumentStack.MetadataDecoder` is `@Sendable (String) -> Metadata?`. Thus `decode(_:) -> AgentFrontmatter?` fits, and `nil` makes the stack send one diagnostic.
    - Extras gives `YAMLValue.parse(_:)`, which parses with Yams. The decode uses it. Thus the unknown keys and the tier 3 keys are a `[String: YAMLValue]` map, and no Node conversion is copied.
    - The Skills colon retry (`FrontmatterDecoder.quotingFallback`) is private to Skills. This package keeps its own copy of the rule: quote the one top-level `description:` line, escape `\` and `"`, keep a trailing `\r`, and give no retry when the value is empty or already quoted.
    - A flow list `[Agent(a, b)]` splits at the comma in YAML. Only the text form and the block list keep `Agent(a, b)` as one entry.
  timestamp: 2026-09-23T14:45:11.194277+00:00
- actor: claude-code
  id: 01m37bz41jqxdmy3p1hfb79dqn
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsAgents/Definition/{AgentFrontmatter,AgentFrontmatterField,AgentFrontmatterReader,DescriptionColonRetry}.swift, Tests/FoundationModelsAgentsTests/AgentFrontmatterTests.swift. `swift test -Xswiftc -warnings-as-errors --filter AgentFrontmatterTests`: 13 tests pass. swiftlint: 0 violations.
    - notes: a 12-case `switch` over the keys failed `cyclomatic_complexity` (12 > 10). The fix is the `AgentFrontmatterField.byKey` table of `WritableKeyPath & Sendable`. A plain `WritableKeyPath` in a `Sendable` enum does not compile.
    - next: test
  timestamp: 2026-09-23T14:50:55.922154+00:00
- actor: claude-code
  id: 01m37c09zkhk8nhpmzjs11kntg
  text: |-
    ### test — green
    - evidence: `swift test -Xswiftc -warnings-as-errors` — 66 tests in 10 suites pass, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples` — 0 violations.
    - next: commit
  timestamp: 2026-09-23T14:51:34.771653+00:00
- actor: claude-code
  id: 01m37c0hfhsyk5hqnmw1vxf9nk
  text: |-
    ### commit — changed
    - evidence: e935c92 feat(definition): decode agent frontmatter with the colon retry
    - next: review HEAD~1..HEAD
  timestamp: 2026-09-23T14:51:42.449884+00:00
- actor: claude-code
  id: 01m37c5vp74xe796qepj7qwjmb
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — findings 0, confirmed 0, refuted 0 (7 files attempted, 2 .kanban files ignored).
    - next: done
  timestamp: 2026-09-23T14:54:36.743255+00:00
- actor: claude-code
  id: 01m37c5xnxe6dwwt61ww6q7qeq
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files under Sources/FoundationModelsAgents/Definition/ and Tests/FoundationModelsAgentsTests/AgentFrontmatterTests.swift
    - test: green — `swift test -Xswiftc -warnings-as-errors`: 66 tests in 10 suites pass; swiftlint 0 violations
    - commit: changed — e935c92
    - review: clean — review sha HEAD~1..HEAD, 0 findings
  timestamp: 2026-09-23T14:54:38.781167+00:00
depends_on:
- 01M376D9AJZB96ZHWEEXGW96QC
- 01M376DZSHS7M9CD50Z24X1ZBZ
position_column: done
position_ordinal: '8680'
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
- [x] The fixture `defaults/agents/code-reviewer.md` frontmatter decodes to the expected values.
- [x] `broken/agents/bad-colon-description.md` decodes after the retry and has one note.
- [x] Invalid YAML after the retry gives `nil`.
- [x] `tools: Read, Grep` and `tools: [Read, Grep]` give the same list; `Agent(a, b)` stays one entry.
- [x] Unknown keys and tier 3 keys are kept for diagnostics.

## Tests
- [x] `Tests/FoundationModelsAgentsTests/AgentFrontmatterTests.swift` covers each criterion and `{{ x }}` staying text.
- [x] Run `swift test --filter AgentFrontmatterTests`. Expected: pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.