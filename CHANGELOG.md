# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
- **Launch video:** `scripts/video/make.sh` renders the launch video and GIFs from the demo home.

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

[Unreleased]: https://github.com/kadaliao/kitfold/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kadaliao/kitfold/compare/f1fb7c2...v0.2.0
[0.1.0]: https://github.com/kadaliao/kitfold/commit/f1fb7c2
