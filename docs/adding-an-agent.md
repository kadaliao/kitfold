# Adding an agent

Kitfold keeps everything agent-specific in a declarative `AgentDescriptor`. Supporting a new agent usually means writing one descriptor, a couple of tests and a research note. The planner, executor and UI don't change.

## 1. Research first, and write down the evidence

Before writing code, find out (for a specific version):

| Question | Why it matters |
|---|---|
| Which folders does it scan for `SKILL.md`, globally and per project? Does it walk up to the repo root? | Skill roots and their scope |
| Which of those folders do other agents also read? | `shared` / `foreign` roles: isolation depends on it |
| On a name clash, who wins: global or project, earlier or later folder? Are both listed? | Root order, `globalSkillsWin` |
| Does it follow symlinked skill folders? Symlinked `SKILL.md` files? | Kitfold deploys links |
| Does it load `SKILL.md` files nested inside a skill? How deep? | `nestedSkillDepth` |
| Which frontmatter fields are required? Is a skill without them skipped? | `requiresName` / `requiresDescription` |
| How can one skill be hidden without deleting it, and in which files and scopes? | `skillDisable` + `NativePolicy` |
| Which instruction files load, in what order, with which fallbacks and overrides? | `instructionFiles` roles |
| Is there a file only this agent reads, globally and per project? | Where Kitfold writes profiles |
| Plugins or extensions that bundle skills? How are they enabled? | `bundledProvider` |

Good evidence, in order: the source code at a version tag, official docs, a reproducible test with a sandbox home. Record the findings in [research.md](research.md), labeled *verified* or *assumption*.

## 2. Write the descriptor

Add it to `Sources/KitfoldCore/Adapters/BuiltinAgents.swift` and to `BuiltinAgents.all`:

```swift
public static let example = AgentDescriptor(
    id: "example", name: "Example", vendor: "Example Inc.",
    binaryNames: ["example"], binaryDirs: ["~/.local/bin"],
    configDir: "~/.example", configDirEnv: "EXAMPLE_HOME",
    skillRoots: [                                   // highest precedence first, per scope
        SkillRootSpec(.configDir, "skills", scope: .global, role: .primary,
                      note: "Only Example reads it."),
        SkillRootSpec(.home, ".agents/skills", scope: .global, role: .shared,
                      note: "Also read by Codex, OpenCode and Gemini CLI."),
        SkillRootSpec(.project, ".example/skills", scope: .project, role: .primary),
    ],
    instructionFiles: [
        InstructionFileSpec(.configDir, "EXAMPLE.md", scope: .global, role: .primary),
        InstructionFileSpec(.project, "EXAMPLE.md", scope: .project, role: .primary),
        InstructionFileSpec(.project, "AGENTS.md", scope: .project, role: .fallback, related: ["EXAMPLE.md"],
                            note: "Read only when EXAMPLE.md is missing.", verified: false),
    ],
    skillDisable: .none, bundledProvider: nil, globalSkillsWin: false,
    nestedSkillDepth: 0, policyCoversBundled: true, requiresName: true, requiresDescription: true,
    instructionByteLimit: nil, docsURL: "https://example.dev/docs/skills",
    monogram: "EX", tint: "#22A06B",
    notes: ["Anything a user should know about how Example loads skills."])
```

**Roles**

| Skill root role | Meaning |
|---|---|
| `primary` | The agent's own folder. Kitfold links skills here. Pick one that only this agent reads. |
| `shared` | A folder several agents read (e.g. `~/.agents/skills`). Kitfold never deploys here implicitly. |
| `foreign` | Another agent's folder this one also reads; set `owner`. |
| `bundled` | Plugins, built-ins, admin folders. Read-only. |

| Instruction file role | Meaning |
|---|---|
| `primary` | Where Kitfold writes profile blocks. Prefer a file only this agent reads. |
| `loaded` | Also loaded; shown in the effective view. |
| `fallback` | Loaded only when none of `related` exist. |
| `override` | Replaces the files in `related` when present and non-empty. |

Paths may end in `/*.md` or `/**/*.md` to match folders of rule files. Mark anything you couldn't confirm with `verified: false`. The UI shows it as unverified.

## 3. Native settings (optional)

If the agent can hide a skill through its own settings:

1. Add a case to `SkillDisableMechanism`.
2. Read it in `NativePolicy.read`. Produce one `NativeRule` per entry, with its file, entry key and value. Take **only** the relevant keys: settings files can hold secrets. `JSONEdit.parse` keeps document order and positions; `MiniTOML` reads simple TOML.
3. Write it in `NativeSettings`:
   - list the files in precedence order (`files`);
   - give the file Kitfold edits for each scope, or nil where the agent can't hide a skill there (`target`);
   - give the entry that hides a skill (`hideEntry`) and, if the agent has one, the entry that forces it on (`showEntry`);
   - implement `set` / `remove` so only that entry changes;
   - add a line to `describe`, so the review sheet can show the entry without showing the file.

Test it end to end, as `NativeSettingsTests` does for the built-in agents: the exact bytes after writing, undo, clearing the rule, and the user's own entries left alone.

For plugin or extension skills, add a `BundledProvider` case and return each enabled plugin's folder from `BundledSkills`.

## 4. Test it

In `Tests/KitfoldCoreTests`, use `FakeHome` to lay out the agent's folders and assert:
- the effective view (`visibleSkills`, `exposures`), including skills it reaches through shared or foreign folders;
- that assigning a skill to the new agent links it into its primary folder and nowhere else (no leaks to other agents);
- fallback and override rules for its instruction files;
- native disables, if implemented.

Then compare Kitfold's view with the agent's own listing on a real machine, read-only (`KITFOLD_HOME=/tmp/x kitfold skills`). Note the result in research.md.

## 5. Finish

- Give it a logo in `Sources/KitfoldApp/AgentLogos.swift`: path data from an SVG, plus the source and license in the header comment. Agents without one get a monogram tile drawn from `monogram` and `tint`.
- Add the agent to the tables in `README.md` and `README.zh-CN.md`.
- Add a CHANGELOG entry under **Unreleased**.
- If the agent needs a demo, extend `scripts/demo/make-demo-home.sh`.
