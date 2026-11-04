# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
