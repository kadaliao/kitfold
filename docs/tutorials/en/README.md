# Kitfold tutorials

Kitfold shows what each coding agent (Claude Code, Codex, OpenCode, Gemini CLI) actually loads, skills and instruction files alike, and lets you give a skill or a Profile to exactly the agents you want. It doesn't do many things, but a few ideas are worth learning first. These tutorials go from the first launch to troubleshooting. Each takes a few minutes, and the screenshots come from the demo home.

## Five ideas to start with

1. **You see what's in effect.** Not just configuration: what each agent really loads, from which folder, and why.
2. **Rules record only what you said.** A skill or profile you never touched stays as it is, which is why the first launch changes nothing.
3. **Draft first, apply later.** Switches only change a draft. You see every file change in the review before anything is written.
4. **Everything can be undone.** Files are backed up before an apply, and any apply can be undone from History.
5. **A link when a link works.** When a link can't hide a skill, Kitfold changes the agent's own setting, and only that one entry.

## Contents

| Tutorial | You'll learn |
|---|---|
| [01 Getting started](01-getting-started.md) | Building and launching, what the first launch does, a tour of the window, Quick Open, switching language |
| [02 What each agent loads](02-what-agents-load.md) | What every group, icon and instruction file on an agent's page means |
| [03 Give skills to the agents you choose](03-assign-skills.md) | Skill detail, the matrix, drag and drop; giving a skill to one agent, or hiding it from one |
| [04 Review, apply, undo](04-review-apply-undo.md) | The pending bar, the review, issues that need attention, History and undo |
| [05 Profiles](05-profiles.md) | Creating and editing profiles, their skills, assigning them, comparing versions, outside edits |
| [06 Per-project setups](06-projects.md) | Adding a project, project skills and profiles, hiding a global skill in one project |
| [07 Your skill library](07-skill-library.md) | New skills, importing folders, moving into the library, deleting skills, skill sources, common skill problems |
| [08 The command line](08-command-line.md) | Every `kitfold` command, the sandbox, scripting |
| [09 Troubleshooting](09-troubleshooting.md) | What each health issue means and what to do, plus common questions |

New here? Read 01–04 in order, then the rest as you need them.

## Try things safely

Everything in these tutorials can be practiced in a sandbox. `make demo DIR=/tmp/kf-demo` builds fictional agents, skills, profiles and projects; then

```bash
KITFOLD_FAKE_HOME=/tmp/kf-demo PATH=/tmp/kf-demo/.local/bin:/usr/bin:/bin .build/debug/KitfoldApp
.build/debug/kitfold --home /tmp/kf-demo status
```

Both read and write only that folder, never your real setup.

## Language

Kitfold follows your system's language. To pick another, use Settings › General › Language; on the command line, `--lang en` or the `KITFOLD_LANG` environment variable. See [01 Getting started](01-getting-started.md).
