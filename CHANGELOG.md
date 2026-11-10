# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Homebrew.** `brew install --cask kadaliao/tap/kitfold` installs Kitfold and links the `kitfold` command into your `PATH`.

### Fixed
- Deleting, moving or editing a skill in `~/.agents/skills` that isn't on the skills CLI's list (`~/.agents/.skill-lock.json`) no longer warns that the skills CLI may bring it back or overwrite it: the skills CLI only touches the skills it installed.

## [0.5.1] - 2026-11-10

### Fixed
- `kitfold update --yes` in Chinese no longer puts a space between its two closing sentences.

## [0.5.0] - 2026-11-10

### Added
- **Updates.** Kitfold checks GitHub for a new release once a day (at launch, or when you come back to it), and shows **Kitfold X is available** in the toolbar. **Install and Reopen** downloads the release's disk image and installs it in place of the running copy, then reopens it.
  - Nothing is replaced unless the download matches the release's SHA-256, is signed by the same Developer ID team as the copy it replaces, is notarized by Apple, and is the version it claims to be. On any failure the old app stays as it was.
  - **Kitfold › Check for Updates…** checks right away. **Skip This Version** stops reminding about that release.
  - Settings › General › **Check for updates automatically** turns the daily check off. It asks GitHub's API for the latest release and sends nothing about you or your setup.
  - A copy run from the disk image, from macOS's temporary location (App Translocation), from a folder you can't write, or a development build can't replace itself; the sheet says why and links to the download page.
- CLI: `kitfold version`, and `kitfold update [--yes]`, which checks for a new release and installs it in place of the Kitfold.app the command belongs to.

## [0.4.0] - 2026-11-10

### Added
- **Every agent, found automatically.** Kitfold now knows 76 agents instead of four, and lists the ones on this Mac: Cursor, GitHub Copilot, Devin (Devin Desktop, formerly Windsurf), Antigravity, Kiro, Trae, Amp, Droid, Goose, Crush, Grok Build, Qwen Code, Kimi Code, CodeBuddy, Lingma, Qoder, Continue, OpenClaw, Pi, Warp, Zed and many more.
  - Each is a line in `AgentCatalog` (`Sources/KitfoldCore/Adapters/AgentCatalog+Specs.swift`): its own skills folders globally and per project, the other folders it reads (`~/.agents/skills`, Claude Code's, Codex's, Cursor's…), the file it reads that Kitfold can write profiles to, and how to tell it's installed. 36 were checked against their docs or source; the rest follow the skills CLI's agent table, and the app marks them unverified.
  - Other agents' folders are modeled too: Cursor, Amp, Goose, Crush, Grok, Augment, Kilo, Devin and fx read Claude Code's `~/.claude/skills`; Warp reads ten agents' folders; Antigravity CLI reads Gemini CLI's. A link made for one agent that reaches another is flagged in the review.
  - An agent counts as installed when its command or app is on this Mac (or its config folder, where that's a reliable sign). One whose folder was only left behind, or made by the skills CLI, is listed but not managed until you switch it on. Agents not on the Mac stay out of the sidebar, the matrix and `kitfold status`; Settings › Agents and `--all` list them.
  - Agents that skip linked skill folders (Continue, fx's `~/.fx/skills`) show those links as skipped, and Kitfold says it can't give them skills by linking.
  - Profiles reach more agents: Amp, Droid, Goose, Crush, Pi, Zed, Junie, Augment, Mistral Vibe, fx, Kilo Code, Kiro, Devin, Antigravity, Trae, Copilot, CodeBuddy, Continue, Grok, Qoder, Kimi Code, Qwen Code and Hermes each get a file of their own, and so do Cursor and Lingma in a project. Where the agent needs frontmatter to apply a rules file every time (Kiro's `inclusion: always`, Cursor's `alwaysApply: true`), Kitfold writes it.
  - **Agents Kitfold doesn't know** are found too: a `skills` folder in `~/.<name>/` or `~/.config/<name>/` that holds skills and that no known agent or source claims is listed as an agent ("found on this Mac"), with what it loads. Such a folder may also be a collection or a repository, so Kitfold manages it only once you switch it on, and never guesses a project folder for it.
  - **Your own agents:** Settings › Agents › **Add Agent…**, or `customAgents` in `kitfold.json` (name, skills folder, optional project folder and instruction files).
  - A folder two agents both read (Trae and Trae CN in a project) belongs to the first; the other is shown reading it, so a link made for one isn't passed off as private.
  - Agents without an instruction file of their own can't get profiles; the profile grids grey them out and the review says why.
- **Remove broken skill links.** Skills deleted outside Kitfold leave links behind in every agent's folder. **Remove these links…** under a broken-link problem, **Remove all N broken links…** on the Dashboard, or `kitfold clean`, take them out, reviewed first and undoable. Broken links to the same skill in several agents' folders are now one problem.
- CLI: `status --all` and `agents --all` list every agent Kitfold knows; `skills` names the agent behind each column; `assign`/`profile` accept found and custom agents.

### Changed
- **Deleting a skill cleans up after it everywhere.**
  - Links to it are taken out of every agent's folder Kitfold knows, not only the four it used to know: the skills CLI's links in `~/.kiro/skills`, `~/.cursor/skills`, `~/.codeium/windsurf/skills` and the rest no longer turn into broken links.
  - A skill the skills CLI installed is also taken off `~/.agents/.skill-lock.json`, as `npx skills remove` does, so `npx skills update` doesn't bring it back. Only that entry changes, and undo puts it back.
  - A skill that's only linked in from elsewhere (a repository checkout) can now be deleted too: its links go, its folder stays where it is.
  - **Delete…** is also in the right-click menu on an agent's page and in the matrix. For plugin and nested skills it's greyed out, with the reason as its help.
- The skill page's **Who gets it** grid has one row per agent and one column per scope, so it stays readable with many agents. The matrix and the profile grids scroll sideways.

### Fixed
- Deleting a skill no longer carries along unrelated changes that were waiting to be applied (for example an "all agents" rule reaching an agent installed since). The review shows only what the delete does; where a file it writes also has other changes waiting (an agent's settings), the review says they come along.

## [0.3.1] - 2026-11-05

### Fixed
- Deleting a skill that another agent loads through a shared folder (OpenCode reads `~/.claude/skills`) no longer warns that the agent "will stop loading" it and suggests switching it on there. Every agent loses a deleted skill.

## [0.3.0] - 2026-11-05

### Added
- **Delete a skill.** **Delete…** on a skill's page (or in the Skills list's context menu), and `kitfold delete <skill>` in the CLI.
  - Kitfold takes back every link to the skill's folder, the entries it wrote for it in the agents' own settings, and its assignments; drops it from the profiles that bundle it; and moves the folder to `~/.kitfold/backups/trash/`.
  - It's reviewed first like any change, and undo puts the folder, the links, the profiles and the assignments back.
  - Skills in the library, in a source and local folders can be deleted. Plugin skills, nested skills and folders reached only through a link can't.
  - The review warns when other agents load the skill from the same folder, when another tool manages the folder or it's a Git clone (an update may bring the skill back), and when another folder has the same name.

## [0.2.0] - 2026-11-05

First prebuilt release: `Kitfold-0.2.0.dmg` on GitHub Releases, a universal app signed with a Developer ID and notarized. `make release` (`scripts/release.sh`) builds it.

### Added
- **Native switches.** When a link can't hide a skill from an agent, Kitfold writes the agent's own setting instead:
  - Claude Code `skillOverrides` (`settings.json`; per project, `.claude/settings.local.json`);
  - Codex `[[skills.config]]`, kept in a marked section at the end of `config.toml` (global only: Codex ignores it per project);
  - OpenCode `permission.skill` (`opencode.json`, global or project);
  - Gemini CLI `skills.disabled` (`settings.json`, global or project).

  This covers skills in shared folders, in another agent's folder (OpenCode reading `~/.claude/skills`), nested skills, and global skills switched off in one project.
  - Only the entry involved changes. The rest of the file keeps every byte, including comments and formatting, and its permissions.
  - The review sheet and the CLI list the entries that change and never show the file, which may hold API keys.
  - Kitfold records which entries it wrote. Clearing the rule takes them back, a file it created is removed once empty, and undo restores both the entries and that record.
  - An explicit "on" can remove the user's own entry that switches a skill off. It's marked caution and can be undone.
- **Agent logos.** Each agent is shown with its own logo, drawn as vectors.
- **New warnings:**
  - a link made for one agent also reaches another agent, or another agent stops seeing a skill (OpenCode reads Claude Code's folder);
  - a non-empty `AGENTS.override.md` means a Codex profile has no effect;
  - an agent skips a skill because its SKILL.md lacks required frontmatter. OpenCode needs `name`, Codex `description`, Gemini CLI both. The effective view now leaves these out.
- **CLI:** `kitfold profiles` lists profile ids and names; `history --project <path>` lists the applies that touched a project; `skills` and `agents` take `--project` for any folder, added or not.
- **OpenCode's switches for Claude Code's skills:** with `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` or `OPENCODE_DISABLE_CLAUDE_CODE` set to a true value, OpenCode is shown not reading `~/.claude/skills` or a project's `.claude/skills` (checked against OpenCode 1.19.4).
- **Simplified Chinese.** The app, the CLI and every message from the core (health checks, previews, errors) are in English and Simplified Chinese.
  - The language follows the system's preferred languages. Pick another in Settings › General › Language; it's stored as Kitfold's own language in macOS, so System Settings › Language & Region › Applications shows the same choice. The app switches at once.
  - The CLI follows the system too; `--lang en|zh-Hans` or `KITFOLD_LANG` overrides it.
  - `LocalizationTests` fails when a string has no translation or a translation is no longer used. See [docs/localization.md](docs/localization.md).
- **Tutorials** in English and Chinese, from the first launch to troubleshooting, with screenshots of the demo home ([docs/tutorials](docs/tutorials/README.md)). Help › Kitfold Tutorials opens them; `scripts/tutorials/make.sh` regenerates the screenshots.
- **Launch video:** `scripts/video/make.sh` renders the launch video and GIFs from the demo home: English and Chinese, 16:9 or 9:16, narrated with Gemini TTS and subtitled.

### Changed
- OpenCode permission rules are applied in file order. Before, the order was guessed.
- Switching a skill off no longer deletes another tool's link when the agent has its own switch. The skill is hidden through that switch instead, so other agents reading the same folder keep it.
- A history entry for a single switch says what it did, e.g. "Take deep-research from OpenCode".
- CLI:
  - unknown options, extra arguments and options without a value are errors (`--of` no longer means "on");
  - `--project` accepts relative paths;
  - `undo` without an id steps back instead of redoing what was just undone;
  - `kitfold.json`'s own diff isn't printed;
  - `assign` and `profile` refuse a rule that can't take effect: a skill or profile id that doesn't exist, or a switch the agent can't make (Codex can't hide a global skill in one project). Nothing is saved; `--force` saves it anyway. `--clear` is always allowed.
- Saving `SKILL.md` is an apply of its own, so History can undo it. Its old text used to go to `backups/skills/` only.
- Files left alone because a profile block in them was edited outside Kitfold are listed under **Not written this time** in the review sheet and the CLI. It's a warning, as in the health check; the review called it an error.
- Counts agree: the pending bar, the review sheet and the CLI count file changes (not `kitfold.json`), and "to check" counts warnings and errors, not notes.
- The app shows profile names instead of ids in reviews and history; so do the CLI's history summaries.
- The agent page lists each skill once, under the route it loads through, and mentions the other folders it's found in.
- A matrix cell whose rule can't take effect is marked, with the reason in its tooltip.
- Skills dropped on an agent go to the scope the Skills page shows. Skills can be dragged from the matrix too; clicking a name there opens its details.
- Quick Open goes to Skills and Profiles too.

### Fixed
- Cleaning up old backups no longer deletes every saved profile version and `SKILL.md` backup. It judged the whole `backups/profiles/` folder by the folder's own date; each version is now judged by its own.
- The project page keeps its overview (agent cards, project profiles) in a small window. The skill matrix below it used to push it out of view.
- Removing a project that still has assignments says to clear them. It used to say to switch them off, which leaves an "off" rule and still blocks removal.
- Saving settings (projects, sources, preferences) no longer blocks undoing an earlier apply. Undo now reverts only that apply's rules.
- Undoing "move into library" is refused while links made later still point into the moved folder.
- Switching off skill `pdf` no longer removes a link named `pdf` that holds a different skill.
- Project paths in `kitfold.json` are expanded (`~`) and must be absolute. Relative ones could resolve against the current folder.
- Backslashes in profile names and descriptions no longer double on every save.
- If the journal can't be written, the files are put back instead of being left changed with no undo.
- Line diffs no longer repeat lines when two changes are close together.
- App:
  - applying a one-off review (editing a file, adopting a skill) keeps unapplied toggles;
  - a rescan requested during a scan runs afterwards instead of being dropped;
  - Apply waits for the latest plan;
  - planning no longer reads shared state off the main thread.
- A skill switched off in an agent's settings is listed once on the agent page, even when the agent finds it in two folders.
- The app reloads `kitfold.json` when the CLI or an editor changes it (on rescan, on the next toggle, and when the app comes back to the front), keeping unapplied toggles on top. Its next apply used to write the old rules back and take back the CLI's links.
- Editing a profile that's assigned shows the pending bar and enables Review Changes. Only Quick Open could apply it.
- "Keep edit" writes the profile when the review is applied, not when it opens; Cancel leaves it alone, and undo restores it.
- "… will load “x” too" and "… will stop loading “x”" are said once per change instead of once per project, and not when that agent has its own rule. A missing skill is one issue per scope, naming every agent.
- Messages:
  - a folder-name conflict suggests deleting the copy or renaming, not importing (which copies and leaves the folder);
  - the skill-name rule mentions `_` and `:`, which it accepts;
  - "If this file is committed…" appears only for project files the user already had;
  - "reaches N skills through two folders" names only the folders involved.
- CLI: `--help` and `-h` work; English plurals ("1 operation", "1 note"); an error now appears after the lines that explain it.
- Chinese: names are listed with “、”, quoted names have no stray spaces, and the sources added on first launch are shown in Chinese until renamed.

### Security
- `state.sqlite` keeps before/after copies of the files Kitfold edits, so it is now owner-only (0600).
- `KITFOLD_FAKE_HOME` no longer follows the real `CODEX_HOME` / `CLAUDE_CONFIG_DIR` out of the fake home.

## [0.1.0] - 2026-11-05

First version.

### Added
- **Agents:** Claude Code, Codex, OpenCode and Gemini CLI, each described declaratively.
  - Kitfold finds each one's binary, version and config folder.
  - It honors `CLAUDE_CONFIG_DIR` / `CODEX_HOME` and per-agent overrides set in Settings.
- **Effective view:** for every agent and project, the skills it actually loads. Each is traced to its source:
  - its own folder, shared folders (`~/.agents/skills`) or another agent's folder;
  - a plugin or extension;
  - a nested `SKILL.md` (Codex and OpenCode only);
  - switched off in the agent's own settings (`skillOverrides`, `[[skills.config]]`, `permission.skill`, `skills.disabled`).
- **Health checks:** broken links (grouped across agents), same-name skills, nested `SKILL.md`, instruction blocks edited outside Kitfold, other tools' managed blocks, and Codex's 32 KiB limit.
- **Context estimate** for each agent: always-loaded skill descriptions plus instruction bytes.
- **Assignments:** turn skills and profiles on or off per agent (or all agents) and per scope (global or project), stored as explicit rules in `~/.kitfold/kitfold.json`.
- **Isolation-first deployment:**
  - Skills are linked into each agent's own folder.
  - Claude Code profiles go to `rules/kitfold.md`, so they reach neither OpenCode nor the AGENTS.md fallback.
  - Kitfold's project files are kept out of git via `.git/info/exclude`.
- **Profiles:** reusable instructions with bundled skills, written as one hash-stamped block per profile, with version history and compare.
- **Planner:**
  - removals and additions are planned in two passes;
  - it warns about shared instruction files and fallback changes;
  - it refuses to write into Kitfold's own library;
  - it never replaces an unknown folder.
- **Executor:**
  - every operation is precondition-checked and backed up first, and a failure rolls back the whole transaction;
  - a SQLite journal and deployment ledger record everything, so any apply can be undone, together with its intent;
  - undo restores relative symlinks exactly as they were.
  - files keep their permissions when rewritten; backups and profile history are owner-only (0600 files, 0700 folder).
- **Library:** create skills and profiles, import folders, add Git repositories or folders as sources, move a skill into the library while leaving a link behind.
- **macOS app:**
  - Dashboard, Skills (list and matrix), per-agent pages, Profiles, Projects and History;
  - a review sheet with diffs, ⌘K quick open, drag a skill onto an agent, and Settings.
- **`kitfold` CLI:** `status`, `skills`, `agents`, `plan`, `assign`, `profile`, `apply`, `history`, `undo`, plus a `--home` sandbox.
- **Tooling:** a release bundle script, a demo home, release screenshots, and a snapshot mode for checking the UI.

[Unreleased]: https://github.com/kadaliao/kitfold/compare/v0.5.1...HEAD
[0.5.1]: https://github.com/kadaliao/kitfold/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/kadaliao/kitfold/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/kadaliao/kitfold/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/kadaliao/kitfold/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/kadaliao/kitfold/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kadaliao/kitfold/compare/f1fb7c2...v0.2.0
[0.1.0]: https://github.com/kadaliao/kitfold/commit/f1fb7c2
