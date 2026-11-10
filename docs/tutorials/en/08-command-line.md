# 08 The command line

Kitfold comes with a command-line tool, `kitfold`. It runs on the same core as the app and uses the same `~/.kitfold`: the same assignment rules, the same preview before anything is applied, the same history. This tutorial shows how to check what each agent loads, assign skills and profiles, and undo changes from a terminal, and how to use `kitfold` in scripts.

## Where the binary is

- **From the repository:** `swift run kitfold status` (builds first), or `make cli ARGS="status"`. After `make build`, the binary is `.build/debug/kitfold`.
- **Inside the app:** `/Applications/Kitfold.app/Contents/Resources/kitfold` when you installed the app from the disk image; `make app` puts it at `build/Kitfold.app/Contents/Resources/kitfold`.

To type `kitfold` from anywhere, link it into a folder on your `PATH`, for example:

```bash
ln -s /Applications/Kitfold.app/Contents/Resources/kitfold ~/.local/bin/kitfold
```

If you move the app, make the link again.

You can mix the app and the command line: changes applied with `kitfold` show up in the app's **History** and can be undone there, and the other way round. When `kitfold.json` changes outside the app, the app reloads it on **Rescan**, on your next switch, and when you come back to its window (and rescans, if `kitfold` applied or undid something). Switches you flipped in the app but haven't applied are kept on top of the new file; where both changed the same switch, the app's change wins. A message says "kitfold.json changed outside Kitfold. Reloaded it and kept your unapplied changes."

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
| `--force` | Save a rule that Kitfold refuses because it can't work (`assign`, `profile`); see [below](#rules-that-cant-work---force) |
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
72 more agents Kitfold knows aren't on this Mac (--all lists them).

Issues (1 warning or error, 1 note)
  ✗ Broken skill link “old-linter”
    ~/.claude/skills/old-linter → ~/.agents/skills/old-linter, which no longer exists. Skipped silently by Claude Code, OpenCode.
```

Running `kitfold` with no command does the same. It lists the agents on this Mac; `--all` lists every agent Kitfold knows. Each agent gets a status (installed; config only, when its folder is here but not its command; folder only, when only a folder left behind is here, which Kitfold doesn't manage until you switch it on) and its version, then the number of skills it actually loads globally, the context it uses in every session (skill names and descriptions plus the loaded instruction files, estimated at 4 bytes per token), and its config folder.

The issues come last: `✗` is an error, `!` a warning. Notes are only counted; to read them, turn on **Show notes** on the app's **Dashboard**. [09 Troubleshooting](09-troubleshooting.md) explains each issue.

### skills: the skill × agent matrix

```console
$ kitfold skills
CC Claude Code, CX Codex, OC OpenCode, GM Gemini CLI
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

Add `--project '~/work/payments-api'` to list the project's folders and files. For `skills` and `agents`, `--project` works with any folder, even one you haven't added as a project.

### profiles: ids and names

```console
$ kitfold profiles
backend-engineer  Backend Engineer  Go services, infra and on-call
code-reviewer     Code Reviewer  Strict, evidence-based reviews
researcher        Researcher  Sourced answers, clear charts
```

Each line has a profile's id, its name and its description. `kitfold profile` takes the id.

### plan: does the disk match kitfold.json?

```console
$ kitfold plan
Nothing to change.
```

`plan` compares the assignments recorded in `~/.kitfold/kitfold.json` with what's on disk and lists the changes needed to make them match. When everything is in order, that's "Nothing to change." The **apply** section below shows when they can drift apart.

## Assigning skills: assign

```
kitfold assign <skill> <agent> [--off | --clear] [--project <path>] [--force] [--yes]
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

Apply 1 file change? Re-run with --yes to apply.
```

The mark in front of each change:

| Mark | Meaning |
|---|---|
| `+ link` / `- link` | Create / remove a link |
| `+ file` / `- file` | Create / delete a file (only files Kitfold created are ever deleted) |
| `~ edit` | Change a file; the lines below show what changes |
| `→ move` | Move a folder (when moving a skill into the library, or deleting one) |
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

Apply 1 file change? Re-run with --yes to apply.
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

Apply 1 file change? Re-run with --yes to apply.
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

Apply 2 file changes? Re-run with --yes to apply.
```

The link goes into the project's own `.gemini/skills`, so it applies in this project only, and Kitfold adds it to `.git/info/exclude` so it isn't committed. If the folder isn't a Kitfold project yet, applying adds it. [06 Per-project setups](06-projects.md) has more on projects.

### Rules that can't work: --force

`assign` and `profile` refuse a rule that can't work, save nothing and return 1. That happens when the skill or the profile id doesn't exist, or when something stands in the way and the rule wouldn't change anything. For example, Codex can't hide a global skill in one project:

```console
$ kitfold assign code-review codex --off --project '~/work/acme-web'
  ! “code-review” stays visible to Codex in this project
    It's enabled globally, and Codex reads `[[skills.config]]` only from $CODEX_HOME/config.toml, so a skill can't be hidden in one project alone. Switch it off globally instead.
error: not saved: this rule wouldn't change anything. --force saves it anyway.
```

A misspelled skill gives "error: no skill named test-writr. kitfold skills --all lists them; --force saves the rule anyway.", and a misspelled profile id lists the ids that exist. Add `--force` to save such a rule anyway. `--clear` is always allowed.

## Assigning profiles: profile

```
kitfold profile <profile id> <agent> [--off | --clear] [--project <path>] [--force] [--yes]
```

A profile's ID is its file name in `~/.kitfold/library/profiles/`, not its display name. In the demo they are `code-reviewer`, `backend-engineer` and `researcher`; `kitfold profiles` lists them (see [above](#profiles-ids-and-names)).

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
    Link data-viz for Gemini CLI (via profile “Researcher”)
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Apply 2 file changes? Re-run with --yes to apply.
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

Apply 4 file changes? Re-run with --yes to apply.
```

Items under **Needs attention** aren't changed automatically; the call is yours. [09 Troubleshooting](09-troubleshooting.md) explains each one. A file whose profile block was edited outside Kitfold is left out and listed under **Not written this time** instead; see [05 Profiles](05-profiles.md#9-a-profile-block-edited-outside-kitfold).

## Deleting a skill: delete

```
kitfold delete <skill> [--yes]
```

`delete` takes a skill away from every agent and moves its folder to Kitfold's trash, `~/.kitfold/backups/trash/`. Like `assign`, without `--yes` it only previews:

```console
$ kitfold delete release-notes
  - link ~/.claude/skills/release-notes
    Unlink release-notes from Claude Code (no longer assigned)
  - link ~/.codex/skills/release-notes
    Unlink release-notes from Codex (no longer assigned)
  → move ~/.kitfold/library/skills/release-notes → ~/.kitfold/backups/trash/release-notes-20261105-154705-f47912
    Move release-notes to Kitfold's trash — The folder is kept in ~/.kitfold/backups/trash, and undo puts it back where it was.
  ~ edit ~/.kitfold/kitfold.json
    Save assignments to kitfold.json

Needs attention
  ! OpenCode will stop loading “release-notes”
    OpenCode found it only in Claude Code's folder ~/.claude/skills. Switch “release-notes” on for OpenCode to keep it there.

Apply 3 file changes? Re-run with --yes to apply.
```

The skill's assignments are cleared, so Kitfold takes back what it made for it, as `--clear` would for every agent: its links and its entries in the agents' own settings. Other links to the folder go too, so none is left broken; one Kitfold didn't make is marked `(caution)`. Profiles that bundle the skill drop it. With `--yes` it's applied, and `kitfold undo` puts it all back.

Deleting from a folder that other agents read, or that another tool manages, says so:

```console
$ kitfold delete pdf-tools
  - link ~/.claude/skills/pdf-tools (caution)
    Remove the link at ~/.claude/skills/pdf-tools — This link wasn't created by Kitfold (another tool or by hand). Undo restores it.
  → move ~/.agents/skills/pdf-tools → ~/.kitfold/backups/trash/pdf-tools-20261105-154705-1084a3 (caution)
    Move pdf-tools to Kitfold's trash — The folder is kept in ~/.kitfold/backups/trash, and undo puts it back where it was.

Needs attention
  ! Codex, OpenCode, Gemini CLI read this folder
    They lose “pdf-tools” when the folder goes.
  ! skills CLI manages ~/.agents/skills
    Deleting the folder doesn't tell skills CLI. Its next update may bring the skill back.

Apply 2 file changes? Re-run with --yes to apply.
```

When several folders have the name, the library's copy is the one deleted, and the preview says the other stays. A skill that's only linked in from a folder outside the library and your sources loses its links, and its folder stays where it is. A skill the skills CLI installed is also taken off `~/.agents/.skill-lock.json`, so `npx skills update` doesn't bring it back. Plugin skills and nested skills can't be deleted:

```console
$ kitfold delete github-pr
error: Invalid: Plugin skills can't be deleted; switch the plugin off in the agent instead
```

## Broken links: clean

```
kitfold clean [--yes]
```

`clean` removes the broken skill links in the folders of the agents on this Mac, managed or not: what's left when a skill's folder was deleted outside Kitfold. Working links stay. Like everything else it previews first, and `kitfold undo` puts the links back.

```console
$ kitfold clean
  - link ~/.claude/skills/old-linter (caution)
    Remove the broken link at ~/.claude/skills/old-linter — It points to ~/.agents/skills/old-linter, which no longer exists.

Apply 1 file change? Re-run with --yes to apply.
```

## History and undo

### history

```console
$ kitfold history
20261105-114616-d3cd65  Take deep-research from OpenCode  2 operations
20261105-114616-608ef8  Give test-writer to Codex  2 operations
20261105-114613-86456e  Give figma-handoff to OpenCode in acme-web  3 operations
…
```

Each apply or undo is one entry, newest first: its ID, a summary and the number of operations. Summaries are stored in the language they were written in and don't change if you switch languages later. Add `--project <path>` to list only the applies that touched files in that project.

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
20261105-114616-0767e2  Undo “Take deep-research from OpenCode”  2 operations
20261105-114616-d3cd65  Take deep-research from OpenCode (undone)  2 operations
20261105-114616-608ef8  Give test-writer to Codex  2 operations
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

Apply 1 file change? Re-run with --yes to apply.
$ kitfold apply --yes
  + link ~/.gemini/skills/code-review → ~/.kitfold/library/skills/code-review
    Link code-review for Gemini CLI (assigned)

Applied. Undo with: kitfold undo 20261105-114630-285e4e
```

In the history, this apply is called "Apply kitfold.json".

## Using it in scripts

- **Preview, then `--yes`.** A command without `--yes` never writes, so a script can run it first to see what would happen.
- **Exit status.** Success and previews return 0. Usage errors, an unknown command or agent, a rule that's refused (see `--force`), and a failed apply or undo return 1, with the message on standard error, starting with "error:":

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

If you forget the syntax, run `kitfold help` (or `kitfold --help`, `kitfold -h`):

```console
$ kitfold help
kitfold status [--all] | plan | apply [--yes] | profiles
kitfold skills [--all] [--project <path>] | agents [--all] [--project <path>]
kitfold assign <skill> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
kitfold profile <id> <agent|*> [--off|--clear] [--project <path>] [--force] [--yes]
kitfold delete <skill> [--yes] | clean [--yes]
kitfold history [--project <path>] | undo [<tx-id>] [--yes]
flags: --home <dir> (sandbox $HOME), --no-color, --lang en|zh-Hans
```

---

[← Previous: 07 Your skill library](07-skill-library.md) · [Contents](README.md) · [Next: 09 Troubleshooting →](09-troubleshooting.md)
