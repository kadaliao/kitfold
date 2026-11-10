# 09 Troubleshooting

Every problem Kitfold finds comes with a title and a short explanation. This tutorial is organized by title: each one is written as the app shows it (with names from the demo data), followed by the explanation text, what it means and what to do. A few common questions come at the end.

## Where issues show up

- **Dashboard › Health** lists errors and warnings. Turn on **Show notes** at the top right of the card to see notes too.
- **Issues** at the bottom of an agent's page lists the issues that concern that agent. An orange triangle next to an agent in the sidebar means it has errors or warnings.
- **Issues in this project** on a project's page lists the issues in that project.
- **Needs attention — not changed automatically** in the review lists issues that only come up when you flip a switch. **Not written this time**, above it, lists files Kitfold leaves out of this apply. "N to check" on the pending bar counts the errors and warnings among them.
- The **Problems** card in a skill's details is about the skill's own `SKILL.md`; see [07 Your skill library](07-skill-library.md).
- **On the command line**, `kitfold status` lists errors and warnings, and the output of `assign`, `profile` and `plan` has "Not written this time" and "Needs attention" sections when there's something to list.

There are three levels: errors (a red icon in the app, `✗` on the command line), warnings (an orange triangle, `!`) and notes (a gray ⓘ, `·`).

## Health issues

These come from scanning, and describe the disk as it is now.

### Broken skill link “old-linter”

> ~/.claude/skills/old-linter → ~/.agents/skills/old-linter, which no longer exists. Skipped silently by Claude Code, OpenCode.

When one folder holds three or more broken links, they're reported together, as in "3 broken skill links in ~/.claude/skills". Broken links to the same skill in several agents' folders are one problem too, as in "3 broken links to “old-linter”".

**What it means:** a link in a skills folder points to a folder that's gone. The agent doesn't complain; it just skips it.

**What to do:** this usually happens when a skill's folder was deleted outside Kitfold: the links the skills CLI (or you) made in each agent's folder stay behind. Click **Remove the link…** (or **Remove these links…**) under the problem, check the review and apply. Kitfold removes only the broken links, whoever made them, and undo puts them back. **Remove all N broken links…** at the top of **Health** on the Dashboard does every one at once; on the command line it's `kitfold clean`.

If Kitfold made the link (its target is in `~/.kitfold/library/skills`), the library skill was deleted or renamed. Bring the skill back, or clear the assignment so it isn't made again. A skill that's gone no longer appears on the app's **Skills** page, so clear it from the command line, for example `kitfold assign k8s-debug codex --clear --yes`.

To delete a skill without leaving links behind, delete it in Kitfold (see [07 The skill library](07-skill-library.md#delete-a-skill)).

### “notes” has no SKILL.md

> ~/.gemini/skills/notes is in a skills folder but isn't a skill.

**What it means:** a link in a skills folder points to a folder without a `SKILL.md`. (A plain folder without `SKILL.md` in a skills folder isn't a skill, and isn't reported.)

**What to do:** if it isn't a skill, move the link out. If it should be one, add a `SKILL.md`.

### Codex sees 2 different skills named “code-review”

> ~/.codex/skills/code-review takes precedence. Also found: ~/.agents/skills/code-review

**What it means:** one agent finds two skills with the same name in different folders. The first one listed is the one it prefers. Some agents list both (Codex); with others, which one wins is hard to predict (OpenCode).

**What to do:** decide which one to keep, then rename the other (its folder and its `name`) or move it away. Select the skill on the **Skills** page: the **Problems** card lists every folder with that name, and in **Where agents load it from**, an entry marked **different folder** is the other copy an agent actually reads. When assigning, Kitfold uses the library copy first.

### OpenCode reaches 6 skills through two folders

> The same skill folders are found via ~/.agents/skills, ~/.claude/skills. Some agents list them twice or warn about a conflict.

This is a note.

**What it means:** one agent finds the same skill folder by two routes. In the demo data, the skills CLI made links in `~/.claude/skills` that point to `~/.agents/skills`, and OpenCode reads both folders.

**What to do:** both routes lead to the same files, so usually nothing. Only if the agent really lists a skill twice or warns about a conflict, remove one route. Don't delete those links in `~/.claude/skills` for OpenCode's sake: Claude Code doesn't read `~/.agents/skills` and relies on them.

### Codex ignores “quick-notes”

> Codex skips skills without a description in SKILL.md. Add it to ~/.agents/skills/quick-notes/SKILL.md.

**What it means:** the skill's frontmatter lacks a field this agent requires, so the agent silently skips it. OpenCode needs `name`, Codex needs `description`, Gemini CLI needs both.

**What to do:** add the missing field to the file named in the message. See [07 Your skill library](07-skill-library.md) for the format.

### “pdf-suite” contains 1 nested SKILL.md

> Codex and OpenCode load each nested SKILL.md as a separate skill: ~/.kitfold/library/skills/pdf-suite/forms/SKILL.md

**What it means:** a subfolder of a skill has its own `SKILL.md`. Codex and OpenCode load it as another, separate skill, even if you only meant the outer one.

**What to do:** if the inner one is just an example or a template, rename the file or move it out. If it really is a skill of its own, give it its own top-level skill folder. To keep one agent from loading it, switch it off for that agent on the **Skills** page; Kitfold writes that agent's own setting.

### Profile “Code Reviewer” was edited outside Kitfold

> ~/.claude/rules/kitfold.md: Kitfold won't overwrite it until you keep or discard the edit.

In the review, the file is listed under **Not written this time** as "~/.claude/rules/kitfold.md won't be written".

**What it means:** someone changed a profile block that Kitfold wrote into an instruction file. Until you decide what to do, Kitfold leaves that file alone; other changes are applied as usual.

**What to do:** open the agent's page and find the file under **Instruction files**. Choose one:

- **Keep edit** opens a review that copies the edit into the profile and rewrites the block; nothing changes until you apply, and undo puts the old profile back;
- **Overwrite…** opens a review that writes the profile's text over the edit.

See [05 Profiles](05-profiles.md) for details.

### Magpie manages part of GEMINI.md

> ~/.gemini/GEMINI.md has a block written by magpie. Kitfold leaves it alone.

This is a note.

**What it means:** the file holds a block managed by another tool (it looks like `<!-- magpie:begin … -->`).

**What to do:** nothing. Kitfold changes only its own blocks.

### Codex instructions exceed 32 KiB

> 34071 bytes are loaded; Codex cuts off everything past 32768 bytes.

**What it means:** Codex reads only the first 32 KiB of instructions. The model never sees the rest.

**What to do:** on Codex's page, **Instruction files** shows which files are loaded and how big each is. Trim them, or move text that isn't needed every time into skills: a skill only costs its name and description until it's used.

### Problems with a skill's SKILL.md

Notes such as "quick-notes: Missing description — agents use it to decide when to load the skill" mean a skill in the library or a source has an untidy `SKILL.md`. They're explained one by one under "Problems shown on a skill" in [07 Your skill library](07-skill-library.md).

## Issues that need attention in the review

These appear in the review after you switch something on or off, under **Needs attention — not changed automatically**. Kitfold won't handle them for you, but you can still apply the rest of the changes.

### “i18n-sync” is switched off in Codex's settings

> ~/.codex/config.toml switches it off for every project, and Codex can't switch it back on for one project. Switch it on globally instead.

**What it means:** you want an agent to load the skill, but the agent's own settings switch it off, and Kitfold can't switch it back on.

When Kitfold can switch it on, it does. Switch `i18n-sync` on for Codex globally, and the review has a change marked **caution**, "Let Codex load i18n-sync again", with the note "Changes an entry Kitfold didn't write. Undo restores it." This issue only appears when that isn't possible.

**What to do:** depends on what the explanation says:

- "…switches it off for every project, and … can't switch it back on for one project": Codex and Gemini CLI can't switch a skill back on in one project once it's off globally. Switch it on globally instead.
- "…switches off every skill (`…`)": a setting turns off all skills. Change it to load skills.
- "…switches it off. Remove that entry to let … load it.": delete that entry yourself.

### “deep-research” stays visible to Codex in this project

> It's enabled globally, and Codex reads `[[skills.config]]` only from $CODEX_HOME/config.toml, so a skill can't be hidden in one project alone. Switch it off globally instead.

**What it means:** you switched off a globally enabled skill in one project, but Codex has no per-project setting for it. Claude Code, OpenCode and Gemini CLI can all hide a global skill in one project; see [06 Per-project setups](06-projects.md).

**What to do:** accept that it stays visible in this project, or switch it off for Codex globally.

### OpenCode will load “test-writer” too

> OpenCode also reads Claude Code's folder ~/.claude/skills. Switch “test-writer” off for OpenCode to keep it to Claude Code.

The opposite case is "OpenCode will stop loading “release-notes”":

> OpenCode found it only in Claude Code's folder ~/.claude/skills. Switch “release-notes” on for OpenCode to keep it there.

**What it means:** Kitfold links the skill into Claude Code's folder, and OpenCode reads that folder too, so OpenCode gets it as well. The other way round, removing the link takes the skill from OpenCode if that's the only place OpenCode found it. For a link in a project, the title names the project, as in "OpenCode will load “test-writer” too in acme-web".

**What to do:** follow the message. To keep the skill to Claude Code, also switch it off for OpenCode (Kitfold writes OpenCode's setting). To let OpenCode keep it, switch it on for OpenCode. Either way OpenCode then has its own rule for the skill, and the warning goes away. You can also leave it; the result is what the message says.

### OpenCode also reads AGENTS.md

> ~/work/payments-api/AGENTS.md is shared, so OpenCode will see Backend Engineer, Researcher too. Agents can't be isolated within one file.

**What it means:** other agents read the instruction file the profile goes into. A project's `AGENTS.md` is read by Codex and OpenCode, and by Claude Code when there's no `CLAUDE.md`. Text in one file can't be shown to just one of them.

**What to do:** nothing to fix; it's a heads-up. If some text mustn't reach another agent, keep it out of profiles that go to a shared file.

### OpenCode will stop reading CLAUDE.md

> Today OpenCode falls back to ~/work/acme-web/CLAUDE.md because ~/work/acme-web/AGENTS.md doesn't exist. Creating it changes that.

**What it means:** some agents fall back to another file when their main file doesn't exist. Kitfold is about to create the main file, so the fallback stops.

**What to do:** if `CLAUDE.md` has text OpenCode needs too, put it in a profile and assign that to OpenCode as well.

### Codex won't read AGENTS.md while AGENTS.override.md exists

> ~/.codex/AGENTS.override.md replaces ~/.codex/AGENTS.md, so the profile has no effect on Codex. Empty or remove the override file, or move its text into a profile.

**What it means:** when a non-empty `AGENTS.override.md` sits next to `AGENTS.md`, Codex reads it instead. Kitfold writes the profile into `AGENTS.md`, which Codex then ignores.

**What to do:** as the message says: empty or delete the override file, or move its text into a profile.

### “github-pr” comes from a plugin

> Plugin skills are managed by the agent's plugin system.

When you switch it off, the explanation reads "Disable the plugin in Claude Code instead."

**What it means:** plugin skills belong to the agent's plugin system. Kitfold can neither assign nor hide them, which is why **Who gets it** for a plugin skill has a sentence instead of cells.

**What to do:** enable or disable the plugin in the agent's own plugin settings.

### Codex can't load “quick-notes”

> Codex skips skills without a description in SKILL.md. Fix ~/.agents/skills/quick-notes/SKILL.md first.

**What it means:** you're giving an agent a skill that lacks frontmatter it requires. The agent would skip it anyway, so Kitfold doesn't make the link.

**What to do:** add the missing field, then assign it again.

### A folder named “test-writer” already exists for Gemini CLI

> ~/.gemini/skills/test-writer is a real folder Kitfold didn't create, so it won't be replaced. If it's a copy of this skill, delete it and apply again; otherwise rename one of the two.

**What it means:** where the link should go, there's already a real folder with the same name. Kitfold never deletes or replaces a real folder.

**What to do:** first check whether they're the same skill. If the folder is a copy of this skill, delete or move it yourself, then apply again. If they're two different skills, rename one.

### Other issues

| Title | What it means | What to do |
|---|---|---|
| Skill “…” isn't in the library | The skill is assigned, but no folder with that name exists anywhere; it may have been deleted or renamed. The explanation names the agents, the project and any profile that includes it | Bring it back, or clear the assignment with `kitfold assign <skill> <agent> --clear --yes`, or drop it from the profile |
| Profile “…” doesn't exist | The assigned profile's file is gone | Remove the assignment or restore the profile file. Deleted profiles are in `~/.kitfold/backups/trash/` |
| Kitfold can't read … | An agent's settings file isn't valid JSON or TOML, so Kitfold won't edit it | Fix the file and try again |
| Kitfold can't add skill settings to … | `config.toml` defines `skills.config` in a form that an appended `[[skills.config]]` table would break | Use `[[skills.config]]` tables there |
| … points into Kitfold's library | The instruction file is a link into Kitfold's library, so writing it would change Kitfold's own data | Replace the link with a regular file |

## When an apply or an undo doesn't go through

**When applying**, a message such as "Precondition failed: … changed since the preview" (or "… already exists", "… is no longer a link", "… now points to …") means something changed a file after the review. Kitfold checks each file again right before writing it. When one doesn't match, it rolls back everything this apply had already done, so nothing is left half-changed. Press ⌘R to rescan, then review again.

**When undoing**, "Precondition failed: These files changed after the original apply, so undo would overwrite newer edits: …" means you or another tool edited the file after that apply. Kitfold won't overwrite newer edits, so nothing is undone. Make a new change instead, such as clicking the cell back, or clearing the rule with `--clear` on the command line. A new change is worked out from the file as it is now and touches only the entries involved, so later edits survive.

When undoing a **Move into Library**, "Links made later still point into …: …. Switch that skill off for those agents first." means agents were given the moved skill after the move. Switch it off for them and apply, then undo.

## Common questions

### Why did a switch write a settings file instead of a link?

Kitfold uses a link whenever a link works: it links the skill into the agent's own skills folder, or takes back a link it made. Some cases can't be handled with a link:

- the skill is in a shared folder (such as `~/.agents/skills`), so removing it would remove it for every agent that reads the folder;
- the agent sees it through another agent's folder (OpenCode reads `~/.claude/skills`), so removing the link would take it from that agent too;
- the skill is nested inside another skill;
- the skill is enabled globally and you want it off in one project.

Then Kitfold changes the agent's own setting:

| Agent | Setting | Global | Per project |
|---|---|---|---|
| Claude Code | `skillOverrides` | `~/.claude/settings.json` | `.claude/settings.local.json` |
| Codex | `[[skills.config]]` | `~/.codex/config.toml` (in a marked section at the end of the file) | Not possible; Codex reads it only globally |
| OpenCode | `permission.skill` | `~/.config/opencode/opencode.json` | The project's `opencode.json` or `.opencode/opencode.json` |
| Gemini CLI | `skills.disabled` | `~/.gemini/settings.json` | `.gemini/settings.json` |

Only the entry involved changes; every other byte of the file stays as it was. The review shows just those entries, never the whole file (it may hold API keys). Kitfold remembers which entries it wrote: when the rule is cleared, it takes them back, and a file it created is removed once it's empty. Entries you wrote yourself are left alone, unless you explicitly ask for the opposite (such as switching on a skill you had switched off). Then the change is marked **caution**, and it can be undone.

### Why does OpenCode see Claude Code's skills?

For compatibility with Claude Code, OpenCode reads `~/.claude/skills` and a project's `.claude/skills` as well as its own folders. So every skill linked into Claude Code's folder is loaded by OpenCode too. That's what the **Via another agent** icon in OpenCode's column of the matrix means, and the `◇` in `kitfold skills`.

To keep a skill to Claude Code, switch it off for OpenCode under **Who gets it**. Kitfold adds a `permission.skill` entry to `opencode.json` that hides it, and Claude Code isn't affected. "OpenCode will load “…” too" in the review is the reminder.

OpenCode skips Claude Code's folders when `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` or `OPENCODE_DISABLE_CLAUDE_CODE` is set to 1, true, yes, on or y. Kitfold checks these too: with one of them set, OpenCode is shown not reading `~/.claude/skills` or a project's `.claude/skills`, and the related warnings go away. Kitfold only sees the variables in its own environment. The command line gets your shell's; the app opened from Finder doesn't see variables exported in a shell profile.

### How do I try things without touching my setup?

- **Use the demo data.** `make demo DIR=/tmp/kf-demo` builds fictional agents, skills, profiles and projects. On the command line, add `--home /tmp/kf-demo`. After `make build`, start the app like this:

  ```bash
  KITFOLD_FAKE_HOME=/tmp/kf-demo PATH=/tmp/kf-demo/.local/bin:/usr/bin:/bin .build/debug/KitfoldApp
  ```

  Both read and write only that folder.
- **Look at your own machine.** `KITFOLD_HOME=/tmp/kf-scratch kitfold status` keeps Kitfold's own data elsewhere and doesn't create `~/.kitfold`. As long as you don't add `--yes`, it only reads.
- **Your real setup is safe to explore too.** On the first launch Kitfold changes nothing except creating its own `~/.kitfold`. After that, every switch only changes a draft, nothing is written until you confirm the review, and every apply can be undone from **History**.

### Where are the backups?

All in `~/.kitfold`:

| Where | What |
|---|---|
| `~/.kitfold/backups/<history ID>/` | Copies of the files an apply overwrote or deleted, including a `SKILL.md` saved in the app. Expand an entry in **History** and click **Backup** to see it in Finder |
| `~/.kitfold/state.sqlite` | The history itself, including the before and after text of the files Kitfold changed. Undo uses this, not the backup folders |
| `~/.kitfold/backups/profiles/` | Saved versions of profiles, the ones **Compare** uses |
| `~/.kitfold/backups/trash/` | Deleted profiles and skills |

How long backups are kept is set in **Settings › General** ("Keep backups for 30 days" by default). Older ones are cleaned up on a later apply, except `trash`. The **History & backups** row on the same tab shows the folder.

### How do I change the language?

- **In the app:** open **Settings › General › Language** and pick **Same as macOS** or a language. The app switches at once; menus and panels drawn by macOS itself follow the next time Kitfold opens. You can also set Kitfold's language under **System Settings › General › Language & Region › Applications**; both are the same setting.
- **On the command line:** add `--lang en` or `--lang zh-Hans`, or set the `KITFOLD_LANG` environment variable. With neither, the system's language is used.

History summaries don't change with the language: they keep the language they were written in. The sources registered on the first launch, "Shared (~/.agents/skills)" and "Magpie library", are shown in the current language unless you've renamed them.

---

[← Previous: 08 The command line](08-command-line.md) · [Contents](README.md)
