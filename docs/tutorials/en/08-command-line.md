# 08 The command line

Kitfold comes with a command-line tool, `kitfold`. It runs on the same core as the app and uses the same `~/.kitfold`: the same assignment rules, the same preview before anything is applied, the same history. This tutorial shows how to check what each agent loads, assign skills and profiles, and undo changes from a terminal, and how to use `kitfold` in scripts.

## Where the binary is

- **From the repository:** `swift run kitfold status` (builds first), or `make cli ARGS="status"`. After `make build`, the binary is `.build/debug/kitfold`.
- **Inside the app:** `make app` puts it at `build/Kitfold.app/Contents/Resources/kitfold`.

To type `kitfold` from anywhere, link it into a folder on your `PATH`, for example:

```bash
ln -s "$PWD/build/Kitfold.app/Contents/Resources/kitfold" ~/.local/bin/kitfold
```

If you move the app, make the link again.

You can mix the app and the command line: changes applied with `kitfold` show up in the app's **History** and can be undone there, and the other way round. One thing to keep in mind: the app reads `kitfold.json` when it starts and doesn't pick up changes made to it afterwards, not even on **Rescan**. If you change assignments with `kitfold` while the app is open, quit and reopen the app before you make more changes in it.

## Try it in a sandbox

```bash
make demo DIR=/tmp/kf-demo
.build/debug/kitfold --home /tmp/kf-demo status
```

`make demo` builds fictional data: four agents, a set of skills, three profiles, two projects (acme-web and payments-api) and a few history entries.

`--home` makes `kitfold` treat that folder as `$HOME`. The agents' folders and Kitfold's own data are all inside it, and your real setup isn't touched.

With `--home`, quote any `~` in a path, as in `--project '~/work/acme-web'`. Then `kitfold` expands `~` to the sandbox, instead of the shell expanding it to your real home folder.

All the output in this tutorial comes from that demo. Every command was run with `--home /tmp/kf-demo --no-color`, which is left out below to keep things short.

## Options

| Option | What it does |
|---|---|
| `--home <dir>` | Treat this folder as `$HOME`, to try things in a sandbox |
| `--project <path>` | Work on a project instead of globally. Relative paths are fine; Kitfold uses the folder's git root |
| `--yes`, `-y` | Actually apply (or undo). Without it you get a preview |
| `--off` | Switch off (`assign`, `profile`) |
| `--clear` | Remove the rule and leave things as found (`assign`, `profile`) |
| `--all` | Make `skills` list skills that no agent loads, too |
| `--lang en\|zh-Hans` | Language of the output. The `KITFOLD_LANG` environment variable does the same; with neither, the system's language is used |
| `--no-color` | No colors. Output that isn't a terminal (a pipe, a file) has none anyway |

Options can go before or after the command. A misspelled option is an error; it's never guessed.

## Looking around

These commands only read. They never change anything.

### status: the overview

```console
$ kitfold status
Kitfold  ~/.kitfold  ·  library: 10 skills, 3 profiles

Claude Code  installed 2.1.318
  9 skills active  ·  ~274 tokens always loaded  ·  config ~/.claude
Codex        installed 0.164.0
  14 skills active  ·  ~298 tokens always loaded  ·  config ~/.codex
OpenCode     installed 1.19.4
  12 skills active  ·  ~267 tokens always loaded  ·  config ~/.config/opencode
Gemini CLI   installed 0.66.0
  11 skills active  ·  ~232 tokens always loaded  ·  config ~/.gemini

Issues (1 warnings/errors, 1 notes)
  ✗ Broken skill link “old-linter”
    ~/.claude/skills/old-linter → ~/.agents/skills/old-linter, which no longer exists. Skipped silently by Claude Code, OpenCode.
```

Running `kitfold` with no command does the same. Each agent gets a status (installed, config only, not found) and its version, then the number of skills it actually loads globally, the context it uses in every session (skill names and descriptions plus the loaded instruction files, estimated at 4 bytes per token), and its config folder.

The issues come last: `✗` is an error, `!` a warning. Notes are only counted; to read them, turn on **Show notes** on the app's **Dashboard**. [09 Troubleshooting](09-troubleshooting.md) explains each issue.

### skills: the skill × agent matrix

```console
$ kitfold skills
                  CC  CX  OC  GM  
api-docs          ·   ◆   ◆   ◆   
code-review       ●   ●   ◇   ●   
commit-message    ○   ◆   ◇   ◆   
deep-research     ○   ◆   ◇   ◆   
frontend-design   ○   ◆   ◇   ◆   
github-pr         P   ·   ·   ·   
i18n-sync         ·   ×   ◆   ◆   
k8s-debug         ·   ●   ·   ·   
notebook-tools    ·   ■   ·   ·   
pdf-tools         ○   ◆   ◇   ◆   
playwright-e2e    ·   ◆   ◆   ◆   
release-notes     ●   ●   ◇   ·   
security-audit    ○   ◆   ◇   ◆   
skill-creator     ·   P   ·   ·   
spreadsheet-ops   ○   ◆   ◇   ◆   
sql-explainer     ·   ◆   ◆   ◆   

● Kitfold link  ○ other link  ■ local folder  ◆ shared dir  ◇ via another agent's dir  n nested in another skill  P plugin  × disabled in agent settings
```

The columns are Claude Code (CC), Codex (CX), OpenCode (OC) and Gemini CLI (GM). Each cell says whether that agent loads the skill, and how it gets there:

| Mark | Meaning |
|---|---|
| ● | A link Kitfold made in the agent's own skills folder |
| ○ | A link made by another tool or by hand |
| ■ | A real folder in the agent's skills folder |
| ◆ | From a shared folder, such as `~/.agents/skills` |
| ◇ | Through another agent's folder, such as OpenCode reading `~/.claude/skills` |
| n | Nested inside another skill |
| P | A plugin |
| × | Present, but switched off in the agent's own settings |
| · | Not loaded |

Take the `code-review` row: Kitfold made a link for Claude Code, Codex and Gemini CLI. OpenCode has no link of its own, yet loads it through Claude Code's folder. `i18n-sync` shows `×` for Codex because `~/.codex/config.toml` switches it off.

By default only skills that at least one agent loads are listed; `--all` lists every skill. Add `--project '~/work/acme-web'` to see a project.

### agents: where each agent looks

```console
$ kitfold agents
Claude Code  managed
  skills folders (precedence order):
    bundled    /Library/Application Support/ClaudeCode/.claude/skills (0)
    primary    ~/.claude/skills (9)
    bundled    ~/.claude/skills/synced (0)
  instruction files:
    /Library/Application Support/ClaudeCode/CLAUDE.md absent
    ~/.claude/CLAUDE.md loaded
    ~/.claude/rules/kitfold.md loaded [kitfold: code-reviewer]

…

OpenCode  managed
  skills folders (precedence order):
    primary    ~/.config/opencode/skills (0)
    foreign    ~/.claude/skills (9)
    shared     ~/.agents/skills (10)
  instruction files:
    ~/.config/opencode/AGENTS.md absent
    ~/.claude/CLAUDE.md loaded
```

Skills folders are listed highest precedence first, with the number of skills found in each. The word before each folder is its role for that agent:

| Role | Meaning |
|---|---|
| `primary` | The agent's own skills folder; Kitfold's links go here |
| `shared` | A folder several agents read, such as `~/.agents/skills` |
| `foreign` | Another agent's folder, such as `~/.claude/skills` for OpenCode |
| `bundled` | Built-in, plugin or system skills |

Instruction files are listed in load order, marked loaded, present but not loaded, or absent. `[kitfold: code-reviewer]` means the file holds a profile block written by Kitfold.

Add `--project '~/work/payments-api'` to list the project's folders and files. For `skills` and `agents`, `--project` only works with a project you've already added (in the app, or by applying an `assign` or `profile` with `--project`).

### plan: does the disk match kitfold.json?

```console
$ kitfold plan
Nothing to change.
```

`plan` compares the assignments recorded in `~/.kitfold/kitfold.json` with what's on disk and lists the changes needed to make them match. When everything is in order, that's "Nothing to change." The **apply** section below shows when they can drift apart.

## Assigning skills: assign

```
kitfold assign <skill> <agent> [--off | --clear] [--project <path>] [--yes]
```

Agents are named by their IDs: `claude-code`, `codex`, `opencode`, `gemini-cli`. `'*'` or `all` means every agent (quote the `*` so the shell leaves it alone).

### Preview first

Without `--yes`, `assign` only prints a preview and changes nothing:

```console
$ kitfold assign test-writer codex
  + link ~/.codex/skills/test-writer → ~/.kitfold/library/skills/test-writer
    Link test-writer for Codex (assigned)
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Apply 2 change(s)? Re-run with --yes to apply.
```

The mark in front of each change:

| Mark | Meaning |
|---|---|
| `+ link` / `- link` | Create / remove a link |
| `+ file` / `- file` | Create / delete a file (only files Kitfold created are ever deleted) |
| `~ edit` | Change a file; the lines below show what changes |
| `→ move` | Move a folder (when moving a skill into the library) |
| `(caution)` | The change touches something Kitfold didn't create |

The preview covers **everything** needed to make the disk match `kitfold.json`. If something else drifted earlier (say, a link Kitfold made was deleted by hand), it's put right in the same apply.

### Apply

When it looks right, run it again with `--yes`:

```console
$ kitfold assign test-writer codex --yes
  + link ~/.codex/skills/test-writer → ~/.kitfold/library/skills/test-writer
    Link test-writer for Codex (assigned)
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Applied. Undo with: kitfold undo 20261105-114616-608ef8
```

### Switch off: --off

```console
$ kitfold assign deep-research opencode --off
  ~ edit ~/.config/opencode/opencode.json
    Hide deep-research from OpenCode
    + permission.skill › "deep-research": "deny"
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Apply 2 change(s)? Re-run with --yes to apply.
```

OpenCode sees `deep-research` through `~/.claude/skills` and the shared folder `~/.agents/skills`. Other agents read those folders too, so deleting a link or the folder would take the skill from them as well. Kitfold changes OpenCode's own setting instead, and only that one entry. For settings files, only the entries that change are shown, never the file (it may hold API keys). [03 Give skills to the agents you choose](03-assign-skills.md) explains why.

### Leave as found: --clear

`--off` is a rule that says "off". `--clear` removes the rule, so Kitfold stops managing that skill for that agent. Kitfold takes back what it made itself (its links, its settings entries) and leaves everything else as it is:

```console
$ kitfold assign test-writer codex --clear
  - link ~/.codex/skills/test-writer
    Unlink test-writer from Codex (no longer assigned)
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Apply 2 change(s)? Re-run with --yes to apply.
```

`--clear` on a skill that has no rule gives "Nothing to change."

### One project only: --project

```console
$ kitfold assign perf-profiler gemini-cli --project '~/work/acme-web'
  + link ~/work/acme-web/.gemini/skills/perf-profiler → ~/.kitfold/library/skills/perf-profiler
    Link perf-profiler for Gemini CLI (assigned)
  ~ edit ~/work/acme-web/.git/info/exclude
    Keep Kitfold's files in acme-web out of git — .git/info/exclude is local to this clone and never committed.
      /.claude/skills/design-tokens
    + /.gemini/skills/perf-profiler
      /.opencode/skills/figma-handoff
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Apply 3 change(s)? Re-run with --yes to apply.
```

The link goes into the project's own `.gemini/skills`, so it applies in this project only, and Kitfold adds it to `.git/info/exclude` so it isn't committed. If the folder isn't a Kitfold project yet, applying adds it. [06 Per-project setups](06-projects.md) has more on projects.

## Assigning profiles: profile

```
kitfold profile <profile id> <agent> [--off | --clear] [--project <path>] [--yes]
```

A profile's ID is its file name in `~/.kitfold/library/profiles/`, not its display name. In the demo they are `code-reviewer`, `backend-engineer` and `researcher`.

```console
$ kitfold profile researcher gemini-cli
  ~ edit ~/.gemini/GEMINI.md
    Update Researcher in ~/.gemini/GEMINI.md — Read by Gemini CLI
    + <!-- kitfold:begin profile=researcher hash=0abfe27fba6b -->
    + ## Researcher
    + 
    + - Use primary sources and link every claim.
    + - Say what is unknown instead of guessing.
    + <!-- kitfold:end profile=researcher -->
    + 
      # Gemini
  + link ~/.gemini/skills/data-viz → ~/.kitfold/library/skills/data-viz
    Link data-viz for Gemini CLI (via profile “researcher”)
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Apply 3 change(s)? Re-run with --yes to apply.
```

The profile goes into the agent's own instruction file as one marked block, and the rest of the file is left alone. Its skills come with it: `data-viz` needs a link, while `deep-research` already reaches Gemini CLI through `~/.agents/skills`.

Anything Kitfold won't handle by itself is listed under **Needs attention**. For example, giving Code Reviewer to every agent in acme-web:

```console
$ kitfold profile code-reviewer '*' --project '~/work/acme-web'
  + file ~/work/acme-web/.claude/rules/kitfold.md
    Create ~/work/acme-web/.claude/rules/kitfold.md with Code Reviewer — Read by Claude Code
  …
  + file ~/work/acme-web/AGENTS.md
    Create ~/work/acme-web/AGENTS.md with Code Reviewer — Read by Codex, OpenCode
  + file ~/work/acme-web/GEMINI.md
    Create ~/work/acme-web/GEMINI.md with Code Reviewer — Read by Gemini CLI
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Needs attention
  ! OpenCode will stop reading CLAUDE.md
    Today OpenCode falls back to ~/work/acme-web/CLAUDE.md because ~/work/acme-web/AGENTS.md doesn't exist. Creating it changes that.

Apply 5 change(s)? Re-run with --yes to apply.
```

Items under **Needs attention** aren't changed automatically; the call is yours. [09 Troubleshooting](09-troubleshooting.md) explains each one.

## History and undo

### history

```console
$ kitfold history
20261105-114616-d3cd65  Take deep-research from OpenCode  2 ops
20261105-114616-608ef8  Give test-writer to Codex  2 ops
20261105-114613-86456e  Give figma-handoff to OpenCode in acme-web  3 ops
…
```

Each apply or undo is one entry, newest first: its ID, a summary and the number of operations. Summaries are stored in the language they were written in and don't change if you switch languages later.

### undo

`undo` without an ID undoes the newest apply that's still in effect. Like every other command, it previews first:

```console
$ kitfold undo
Undo “Take deep-research from OpenCode” (2 operations)
  Save assignments to kitfold.json
  Hide deep-research from OpenCode

Re-run with --yes to undo.
$ kitfold undo --yes
Undo “Take deep-research from OpenCode” (2 operations)
  Save assignments to kitfold.json
  Hide deep-research from OpenCode
Undone.
```

The undo takes back the assignment rule along with the files: the entry in `opencode.json` is gone again. The undo is itself a history entry:

```console
$ kitfold history
20261105-114616-0767e2  Undo “Take deep-research from OpenCode”  2 ops
20261105-114616-d3cd65  Take deep-research from OpenCode (undone)  2 ops
20261105-114616-608ef8  Give test-writer to Codex  2 ops
…
```

Running `kitfold undo --yes` again undoes the apply before that one (here, "Give test-writer to Codex"); it doesn't redo what you just undid. To undo a particular entry, give its ID: `kitfold undo 20261105-114616-608ef8 --yes`.

Before undoing, Kitfold checks every file involved. If one has changed since that apply, nothing is undone, and you're told which file:

```console
$ kitfold undo --yes
Undo “Take deep-research from OpenCode” (2 operations)
  Save assignments to kitfold.json
  Hide deep-research from OpenCode
error: Precondition failed: These files changed after the original apply, so undo would overwrite newer edits: ~/.config/opencode/opencode.json
```

In that case, make a new change instead, such as `kitfold assign deep-research opencode --clear --yes`. It takes back only the entry Kitfold wrote and keeps the edit made since.

## apply: bring the disk back to kitfold.json

`assign` and `profile` apply their own changes, so you rarely need `apply`. It's for when something outside Kitfold changed the disk, for example when someone deleted the `code-review` link Kitfold had made for Gemini CLI:

```console
$ kitfold plan
  + link ~/.gemini/skills/code-review → ~/.kitfold/library/skills/code-review
    Link code-review for Gemini CLI (assigned)
$ kitfold apply
  + link ~/.gemini/skills/code-review → ~/.kitfold/library/skills/code-review
    Link code-review for Gemini CLI (assigned)

Apply 1 change(s)? Re-run with --yes to apply.
$ kitfold apply --yes
  + link ~/.gemini/skills/code-review → ~/.kitfold/library/skills/code-review
    Link code-review for Gemini CLI (assigned)

Applied. Undo with: kitfold undo 20261105-114630-285e4e
```

In the history, this apply is called "Apply kitfold.json".

## Using it in scripts

- **Preview, then `--yes`.** A command without `--yes` never writes, so a script can run it first to see what would happen.
- **Exit status.** Success and previews return 0. Usage errors, an unknown command or agent, and a failed apply or undo return 1, with the message on standard error, starting with "error:":

  ```console
  $ kitfold assign test-writer claude
  error: unknown agent claude (known: claude-code, codex, opencode, gemini-cli, *)
  ```

  `status` and `plan` return 0 even when they list issues.
- **Pin the language if you parse the output.** With `--lang en`, the text doesn't change with the system's language. Add `--no-color` too (output to a pipe has no colors anyway).
- **Each `--yes` is its own history entry**, so `kitfold undo --yes` steps back one at a time.

For example, a script that sets up a new machine:

```bash
#!/bin/sh
set -e
kitfold assign code-review '*' --yes
kitfold assign test-writer codex --yes
kitfold profile code-reviewer claude-code --yes
kitfold profile backend-engineer codex --project ~/work/payments-api --yes
```

If you forget the syntax, run `kitfold help`:

```console
$ kitfold help
kitfold status | skills [--all] | agents | plan | apply [--yes]
kitfold assign <skill> <agent|*> [--off|--clear] [--project <path>] [--yes]
kitfold profile <id> <agent|*> [--off|--clear] [--project <path>] [--yes]
kitfold history | undo [<tx-id>] [--yes]
flags: --home <dir> (sandbox $HOME), --no-color, --lang en|zh-Hans
```

---

[← Previous: 07 Your skill library](07-skill-library.md) · [Contents](README.md) · [Next: 09 Troubleshooting →](09-troubleshooting.md)
