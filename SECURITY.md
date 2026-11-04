# Security Policy

Kitfold reads and writes configuration files that belong to other tools: agent skills folders, instruction files and, when native toggles land, agent settings files. Those settings files can contain credentials. We treat file-safety and secret-handling bugs as security issues.

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x | ✅ |

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private vulnerability reporting instead: open the repository's **Security** tab, then **Report a vulnerability**. Include:

- what an attacker or a bug can cause (e.g. overwriting a file Kitfold doesn't own, leaking a settings value, escaping a sandbox path);
- steps to reproduce, preferably in a sandbox home (`scripts/demo/make-demo-home.sh`);
- the Kitfold commit and macOS version.

You'll get an acknowledgement within a week. Once a fix is ready we coordinate disclosure with you, and credit you unless you'd rather we didn't.

## What counts

In scope, for example:
- Kitfold writing, deleting or replacing anything outside the change you previewed;
- undo or rollback leaving files in a state other than the original;
- reading, displaying, logging or storing settings values other than the keys Kitfold needs;
- backups or state files created with looser permissions than the files they copy;
- symlink tricks that make Kitfold write outside the intended target.

Out of scope: what an agent does with the skills and instructions you give it, and issues that need an attacker who can already write to your home directory.

## How Kitfold limits risk

- Only four operations: create a link, remove a link, write a file, move a folder. Each is reversible and journaled.
- Every operation re-checks its precondition (exact file content, exact link target) right before running. A mismatch aborts and rolls back the transaction.
- Unknown folders are never replaced; other tools' managed blocks are never edited.
- Writes into a file that resolves to Kitfold's own library are refused, which prevents feedback loops.
- Agent settings are parsed in-process for specific keys only (`skillOverrides`, `[[skills.config]]`, `permission.skill`, `skills.disabled`, `enabledPlugins`).
