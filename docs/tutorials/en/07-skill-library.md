# 07 Your skill library

This tutorial covers where each skill in Kitfold comes from, and how to create a skill, edit its `SKILL.md`, import a skill folder from elsewhere, move a stray skill into the library, and read the problems listed on a skill's page.

## Where skills come from

The **Skills** page lists every skill Kitfold found on this Mac. Next to each skill's name is a label that says where it lives:

| Label | Where | Loaded without an assignment? | Editable in Kitfold? |
|---|---|---|---|
| Library | `~/.kitfold/library/skills`, Kitfold's own library | No. It's linked into an agent's folder when you assign it | Yes |
| Source | A folder Kitfold reads in place: `~/.agents/skills`, a folder you added, a cloned Git repository | Depends on the folder. Codex, OpenCode and Gemini CLI read `~/.agents/skills` directly; a folder you added is read by no agent | Yes |
| Local folder | A real folder sitting directly in an agent's skills folder, such as `~/.codex/skills/notebook-tools` | Yes, by that agent (and any agent that reads its folder) | Yes |
| Linked folder | A link in an agent's skills folder that points somewhere Kitfold doesn't know | Yes | Yes |
| Plugin | An agent's plugin, extension or built-in skill, such as a Claude Code plugin or Codex's `.system` skills | Up to the agent's plugin system | No, read-only |
| Nested | A `SKILL.md` inside another skill's folder | Codex and OpenCode load it as a separate skill | Can't be moved on its own |

On the first launch, if `~/.agents/skills` exists, Kitfold registers it as a source. If `~/.agents/.skill-lock.json` exists, the source is marked "skills CLI", meaning that tool manages the folder. If Magpie is installed, its library `~/.config/magpie/library/skills` is registered too.

To look at one kind at a time, use the filter menu in the **Skills** toolbar: **All**, **Library**, **Sources**, **Local folders**, **Plugins**, **With problems**. On the **Dashboard**, the **Skill folders** card counts the skills of each kind and lists the registered sources.

![The Skills page: the skill list on the left, code-review's details on the right](../images/en/skill.jpg)

## Create a skill

1. Press ⇧⌘N, or click **Add › New Skill…** on the **Skills** page. (It's also under **Quick actions** on the Dashboard and in ⌘K Quick Open.)
2. Type a name, such as `api-changelog`. Use lowercase letters, digits and hyphens: Kitfold lowercases what you type and turns spaces and punctuation into hyphens, and the result becomes both the folder name and `name`.
3. In the second field, say in one sentence when an agent should use it. This becomes `description`. Agents use it to decide when to load the skill, and Codex and Gemini CLI skip skills that have none.
4. Click **Create**.

![The New Skill sheet](../images/en/new-skill.jpg)

Kitfold creates `~/.kitfold/library/skills/api-changelog/SKILL.md` and selects it on the **Skills** page:

```markdown
---
name: api-changelog
description: Summarize API changes between two release tags.
---

# api-changelog

Describe when and how to use this skill.
```

A new skill isn't given to any agent. Once you've written the body, click the cells under **Who gets it** to hand it out, as described in [03 Give skills to the agents you choose](03-assign-skills.md).

## Edit SKILL.md

1. Select the skill on the **Skills** page.
2. On the **SKILL.md** card at the bottom of the details, click **Edit**.
3. Make your changes and click **Save** (⌘S), or **Cancel**.

To use your own editor instead, click **Open** below the skill's name. The `SKILL.md` opens in your default app for Markdown.

Saving works differently from an assignment:

- **It's written straight away, without a review.** The file changes at once. The save doesn't appear in **History** and can't be undone there.
- **The previous version is kept.** Before each save, Kitfold copies the old text to `~/.kitfold/backups/skills/<folder>/`, so you can get it back.
- **Every agent that uses the skill gets the new text.** Agents' folders hold links to this folder, so the next time an agent loads its skills it reads the new version. Nothing needs applying.
- **Folders managed by another tool.** If the skill's source belongs to the skills CLI or Magpie, the editor warns that the tool's next update may replace your edits. To change such a skill for good, move it into the library first (see below).
- **Plugin skills are read-only.** They have no **Edit** button.

## The frontmatter each agent requires

The part of `SKILL.md` between the `---` lines is the frontmatter. Agents require different fields, and an agent **silently skips** a skill that lacks one:

| Agent | Requires | Without it |
|---|---|---|
| Claude Code | Nothing; `name` defaults to the folder name | Loads it anyway |
| Codex | `description` | Skips it |
| OpenCode | `name` | Skips it |
| Gemini CLI | `name` and `description` | Skips it |

So write both, with `name` matching the folder name. Kitfold checks this for you. A skill that an agent will skip shows up in **Health** as a warning such as "Codex ignores “…”". If you try to give it to an agent that would skip it, the review lists "… can't load “…”" and Kitfold doesn't create that link.

## Import a folder

You have a skill folder (say, downloaded from someone's repository) and want a copy in Kitfold's library:

1. On the **Skills** page, click **Add › Import Folder…**.
2. Choose the folder. It must contain a `SKILL.md`.

Kitfold **copies** the whole folder to `~/.kitfold/library/skills/<name>`, using `name` from the frontmatter, or the folder name if there's none. The original folder is left untouched, and the skill isn't given to any agent.

If the library already has a skill with that name, the import fails with "The library already has a skill named …". Rename one of them first.

## Move into the library

**Move into Library** is different from importing: it **moves** the folder into the library and leaves a link to it in the old place. Agents and tools that used the old path keep working, and from then on the library holds the only copy, which you manage in Kitfold.

A typical case in the demo data is Codex's `notebook-tools`: a real folder someone put in `~/.codex/skills` by hand, labeled **Local folder**.

1. Select `notebook-tools` on the **Skills** page.
2. Click **Move into Library** below the skill's name.
3. The review lists what will happen:
   - Move notebook-tools into the Kitfold library;
   - Leave a link at `~/.codex/skills/notebook-tools` (agents and tools that used the old path keep working);
   - Save assignments to `kitfold.json`: each agent that had the skill as a real folder in its own folder (here, Codex) gets an "on" rule, so Kitfold treats the new link as intended rather than as a leftover.
4. Click **Apply**.

The move is recorded in **History** as "Adopt notebook-tools" and can be undone.

A few notes:

- Skills already in the library, plugin skills and nested skills don't have this button.
- If the skill comes from a source another tool manages (such as `~/.agents/skills`, managed by the skills CLI), the review warns that after the move the tool may treat the skill as replaced by a link, and its updates will no longer reach it.
- If the library already has a folder with that name, Kitfold refuses the move.

## Skill sources

A source is a skill folder Kitfold **reads in place**: nothing is copied, and its skills are simply listed for you to assign.

**Add a local folder:** on the **Skills** page, click **Add › Add Source Folder…** and choose a folder of skills. Kitfold looks one level down: each subfolder with a `SKILL.md` is a skill.

**Add a Git repository:** click **Add › Add Git Repository…**, enter the repository's URL and click **Clone**. Kitfold makes a shallow clone in `~/.kitfold/sources/<repository name>` and lists every folder with a `SKILL.md`, a few levels deep. Kitfold doesn't pull updates for you; run `git pull` in that folder when you want them.

Either way, nothing is given to any agent. Assign the skills you want.

**Manage sources:** open **Settings** (⌘,) and go to the **Sources** tab. **Skill folders Kitfold reads in place** lists each source with its name, path and the tool that manages it. Click the minus button to remove one. Removing a source only stops Kitfold from reading it; no files are deleted. The Kitfold library (`~/.kitfold/library`) is always included and isn't in this list.

## Problems shown on a skill

When something is wrong with a skill's `SKILL.md`, an orange exclamation mark appears next to its name in the list, and its details get a **Problems** card. Choose **With problems** in the filter menu to find them all.

| Problem | Meaning | What to do |
|---|---|---|
| SKILL.md has no frontmatter (name/description) | The file doesn't start with a frontmatter block between `---` lines | Add `name` and `description`, as in the template above |
| Missing description — agents use it to decide when to load the skill | `description` is missing or empty | Write one sentence on when to use it. Codex and Gemini CLI skip skills without one |
| Name “…” should be lowercase letters, digits and hyphens | `name` has capitals, spaces or other characters | Use a name like `api-changelog` |
| Frontmatter is not closed with --- / Frontmatter has no readable keys / Unreadable frontmatter line: … | The frontmatter can't be read | Fix its format against the template |
| 2 folders are named “…”. Agents pick one; Kitfold assigns the library copy first. | Skills with the same name live in different places | The card lists the other folder's path. Keep one, or rename one of them |

For skills in the library and in sources, the **Dashboard**'s **Health** card lists these problems too, as notes: turn on **Show notes** to see them. Nested `SKILL.md` files, name clashes and skills an agent skips appear in **Health** directly. [09 Troubleshooting](09-troubleshooting.md) explains them and what to do.

---

[← Previous: 06 Per-project setups](06-projects.md) · [Contents](README.md) · [Next: 08 The command line →](08-command-line.md)
