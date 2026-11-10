# Adding an agent

Kitfold keeps everything agent-specific in a declarative `AgentDescriptor`. Supporting a new agent usually means writing one descriptor, a couple of tests and a research note. The planner, executor and UI don't change.

There are three ways an agent gets into Kitfold:

| | Where | For |
|---|---|---|
| **Built-in** | `BuiltinAgents.swift`, a full `AgentDescriptor` | Agents described in depth: instruction-file fallbacks, native "hide skill" settings, plugins. Claude Code, Codex, OpenCode, Gemini CLI. |
| **Catalog** | `AgentCatalog+Specs.swift`, one `AgentSpec` line | Agents that keep skills the common way: a folder of their own globally and per project, maybe `~/.agents/skills`, maybe Claude Code's folders. |
| **Found or custom** | at scan time (`AgentDiscovery`) or `customAgents` in `kitfold.json` | Agents Kitfold doesn't know. Nothing to add to the code. |

## A catalog agent

Most new agents only need a line in `AgentCatalog.specs`:

```swift
AgentSpec(
    "example", "Example", vendor: "Example Inc.", home: "~/.example", binaries: ["example"],
    skills: ["skills"],                       // own global folders (the first gets Kitfold's links), relative to `home` or ~/…
    projectSkills: [".example/skills"],       // own project folders
    agentsGlobal: true, agentsProject: true,  // also reads ~/.agents/skills, .agents/skills
    claudeGlobal: true, claudeProject: true,  // also reads Claude Code's folders
    reads: ["~/.cursor/skills"], projectReads: [".cursor/skills"],  // any other folders it reads
    instructions: [AgentSpec.ownInstructions("rules/kitfold.md", header: AgentSpec.alwaysOnRuleHeader)],
    docs: "https://example.dev/docs/skills", tint: "#22A06B",
    markers: ["/Applications/Example.app"], configDirMeansInstalled: false, verified: true),
```

- `home` is the agent's config folder. By default its existence means the agent is installed. Where the folder often outlives the agent, or another tool creates it (the skills CLI makes `~/.kiro/skills`), set `configDirMeansInstalled: false`: then the command (`binaries`) or a `markers` path (an app bundle; `prefix*` matches a versioned extension folder) decides, and a folder alone shows the agent as listed but not managed. List in `binaries` only command names no other common tool uses (`goose`, `forge`, `pi`, `fx` and `hermes` are taken).
- `reads` and `projectReads` name the folders it reads besides its own. Whose they are is worked out from the other agents: `~/.agents/skills` and `~/.config/agents/skills` are shared, and a folder another agent calls its own becomes `foreign` with that owner, so the review warns that a link for that agent reaches this one too. `readsFirst` puts them ahead of its own folders, and `readsSkippedWhen` / `claudeSkippedWhen` name environment variables that switch them off.
- `followsLinks: false` (and `projectFollowsLinks`) for an agent that skips linked skill folders (fx's `~/.fx/skills`, Continue): links there are shown as skipped, and Kitfold doesn't deploy there.
- `instructions`: a file this agent alone reads, where Kitfold writes profiles (`AgentSpec.ownInstructions`). `header` is frontmatter Kitfold writes first when it creates the file, for agents that apply a rules file every time only with it (Kiro's `inclusion: always`, Cursor's `alwaysApply: true`, Devin's and Antigravity's `trigger: always_on`). A file another agent's profile file also reaches can be listed with role `.loaded`, so the review warns.
- A folder two agents both call their own belongs to the first in the list; the second is given it as another agent's folder (`foreign`), so Kitfold warns that a link made for one reaches both.
- `verified: false` (the default) marks folders taken from the skills CLI's agent table rather than the agent's own docs. The app shows them as unverified. Set `verified: true` once you've checked them, and note the source in [research.md](research.md) §8.
- Give it `instructions` only for a file that this agent alone reads; without one, profiles can't be given to it, and the app says so.
- Notes shown for catalog agents are shared (`AgentSpec.Notes`) so they're translated once. A spec's own `notes` need a translation in `Translations+zhHansAgents.swift`; `LocalizationTests` checks.

`AgentCatalogTests.catalogIsWellFormed` checks ids, names and that no folder is two agents' own.

## Found and custom agents

On every scan `AgentDiscovery` looks at `~/.<name>/skills` and `~/.config/<name>/skills`. A folder that holds at least one skill and that no known agent (built-in, catalog, custom) or skill source claims becomes an agent named after the folder (id `<name>`, or `<name>-config` / `<name>-home` when that's taken). It has no project folder, since one could only be guessed, and it isn't managed until the user switches it on in Settings › Agents: the folder may be a collection or a repository checkout rather than an agent's.

Users describe anything else in Settings › Agents › **Add Agent…**, or in `kitfold.json`:

```json
"customAgents": [
  { "id": "lab", "name": "Lab Agent", "skills": "~/lab/agent-skills",
    "projectSkills": ".lab/skills", "instructions": "~/lab/RULES.md", "projectInstructions": "RULES.md" }
]
```

A custom agent with the id of a known one replaces it, and its folder is no longer "found" as another agent. If an agent keeps turning up this way, add it to the catalog.

The rest of this page is about built-in agents, the in-depth kind.

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

Add it to `Sources/KitfoldCore/Adapters/BuiltinAgents.swift` and to `BuiltinAgents.all` (and remove its catalog line, if it had one):

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
- Add the agent to the tables in `README.md` and `README.zh-CN.md` (built-in agents) or to the list under them (catalog agents).
- Add a CHANGELOG entry under **Unreleased**.
- If the agent needs a demo, extend `scripts/demo/make-demo-home.sh`.
