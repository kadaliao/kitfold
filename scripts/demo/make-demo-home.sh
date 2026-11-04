#!/bin/bash
# Build a fictional but realistic $HOME for screenshots and UI checks.
# Nothing here touches your real home: everything lives under the directory you pass.
#
#   scripts/demo/make-demo-home.sh /tmp/kitfold-demo
#   KITFOLD_FAKE_HOME=/tmp/kitfold-demo PATH=/tmp/kitfold-demo/.local/bin:/usr/bin:/bin swift run KitfoldApp
set -euo pipefail
cd "$(dirname "$0")/../.."

H="${1:?usage: make-demo-home.sh <dir>}"
rm -rf "$H"
mkdir -p "$H"
H="$(cd "$H" && pwd -P)"

skill() {  # skill <dir> <name> <description> [body]
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: %s\n---\n\n# %s\n\n%s\n' "$2" "$3" "$2" "${4:-Follow the steps below.}" > "$1/SKILL.md"
}

# --- Agent CLIs (stand-ins that only answer --version) ---
mkdir -p "$H/.local/bin"
for pair in "claude:2.1.318 (Claude Code)" "codex:codex-cli 0.164.0" "opencode:1.19.4" "gemini:0.66.0"; do
  name="${pair%%:*}"; ver="${pair#*:}"
  printf '#!/bin/sh\necho "%s"\n' "$ver" > "$H/.local/bin/$name"
  chmod +x "$H/.local/bin/$name"
done

# --- Shared skills installed by the skills CLI (~/.agents/skills) ---
S="$H/.agents/skills"
skill "$S/pdf-tools"        pdf-tools        "Read, split, merge and fill PDF forms. Use for any task involving .pdf files."
skill "$S/spreadsheet-ops"  spreadsheet-ops  "Create and edit .xlsx files with formulas, pivots and charts."
skill "$S/deep-research"    deep-research    "Plan multi-source research and write a cited, structured report."
skill "$S/frontend-design"  frontend-design  "Build distinctive, production-grade interfaces with a clear visual direction."
skill "$S/api-docs"         api-docs         "Generate OpenAPI reference docs from route handlers and examples."
skill "$S/sql-explainer"    sql-explainer    "Explain and optimize SQL queries using EXPLAIN plans and index hints."
skill "$S/commit-message"   commit-message   "Write conventional commit messages from the staged diff."
skill "$S/security-audit"   security-audit   "Review code for injection, auth, secrets handling and unsafe dependencies."
skill "$S/playwright-e2e"   playwright-e2e   "Write and debug Playwright end-to-end tests with stable selectors."
skill "$S/i18n-sync"        i18n-sync        "Find missing translation keys and keep locale files in sync."
echo '{"version":3,"skills":{},"dismissed":{},"lastSelectedAgents":["claude-code","codex","opencode","gemini-cli"]}' > "$H/.agents/.skill-lock.json"

# --- Claude Code: links made by the skills CLI, one stale link, a plugin ---
mkdir -p "$H/.claude/skills"
for s in pdf-tools spreadsheet-ops deep-research frontend-design commit-message security-audit; do
  ln -s "../../.agents/skills/$s" "$H/.claude/skills/$s"
done
ln -s "../../.agents/skills/old-linter" "$H/.claude/skills/old-linter"
P="$H/.claude/plugins/cache/acme-plugins/github-pr/1.2.0"
skill "$P/skills/github-pr" github-pr "Open, review and land GitHub pull requests from the terminal."
cat > "$H/.claude/plugins/installed_plugins.json" <<JSON
{"version": 2, "plugins": {"github-pr@acme-plugins": [{"scope": "user", "installPath": "$P", "version": "1.2.0"}]}}
JSON
echo '{"enabledPlugins": {"github-pr@acme-plugins": true}}' > "$H/.claude/settings.json"
cat > "$H/.claude/CLAUDE.md" <<'MD'
# Personal notes

- Prefer small, reviewable commits.
- Ask before running anything that costs money.
MD

# --- Codex: a hand-made folder, a built-in skill, one skill switched off in config ---
skill "$H/.codex/skills/notebook-tools" notebook-tools "Run and tidy Jupyter notebooks; strip outputs before commit."
skill "$H/.codex/skills/.system/skill-creator" skill-creator "Create a new skill with the right structure and frontmatter."
cat > "$H/.codex/config.toml" <<TOML
model = "gpt-6.1"

[[skills.config]]
path = "$S/i18n-sync/SKILL.md"
enabled = false
TOML
printf '# Codex\n\nKeep answers short. Run tests before saying something works.\n' > "$H/.codex/AGENTS.md"

# --- OpenCode / Gemini CLI ---
mkdir -p "$H/.config/opencode" "$H/.gemini/skills"
echo '{"$schema": "https://opencode.ai/config.json"}' > "$H/.config/opencode/opencode.json"
printf '# Gemini\n\nCite sources for every claim.\n' > "$H/.gemini/GEMINI.md"

# --- Kitfold library ---
L="$H/.kitfold/library"
skill "$L/skills/code-review"      code-review      "Review diffs for correctness, regressions and missing tests. Report only real problems."
skill "$L/skills/release-notes"    release-notes    "Turn merged pull requests into clear, user-facing release notes."
skill "$L/skills/k8s-debug"        k8s-debug        "Diagnose failing pods, probes and rollouts with kubectl and events."
skill "$L/skills/terraform-plan"   terraform-plan   "Read terraform plans and flag destructive or risky changes."
skill "$L/skills/design-tokens"    design-tokens    "Keep Figma variables and CSS design tokens in sync."
skill "$L/skills/figma-handoff"    figma-handoff    "Turn Figma frames into component specs with states and spacing."
skill "$L/skills/test-writer"      test-writer      "Write focused unit tests for the code that changed."
skill "$L/skills/incident-runbook" incident-runbook "Walk through incident triage step by step using team runbooks."
skill "$L/skills/data-viz"         data-viz         "Choose the right chart for a dataset and build it cleanly."
skill "$L/skills/perf-profiler"    perf-profiler    "Profile hot paths, read flame graphs and propose targeted fixes."
cat > "$L/skills/code-review/SKILL.md" <<'MD'
---
name: code-review
description: Review diffs for correctness, regressions and missing tests. Report only real problems.
---

# Code review

Review the change the way a careful senior engineer would.

## Steps
1. Read the diff and the code around it.
2. Check behavior changes against callers and tests.
3. Look for missing error handling at boundaries.

## Report
| Severity | When to use |
|---|---|
| **Blocker** | Wrong behavior, data loss, security issue |
| **Should fix** | Missing test for changed behavior |
| **Nit** | Style; only if it hurts readability |

- Quote the exact line.
- Explain the failing input, not just the rule.
MD
mkdir -p "$L/profiles"
cat > "$L/profiles/code-reviewer.md" <<'MD'
---
name: Code Reviewer
description: Strict, evidence-based reviews
skills:
  - code-review
  - security-audit
order: 10
---
## Code Reviewer

- Review only what changed; cite file and line.
- Every finding needs a concrete failing input.
- Prefer one clear blocker over ten nits.
MD
cat > "$L/profiles/backend-engineer.md" <<'MD'
---
name: Backend Engineer
description: Go services, infra and on-call
skills:
  - k8s-debug
  - terraform-plan
  - test-writer
order: 20
---
## Backend Engineer

- Services are Go 1.30; keep handlers thin and testable.
- Every schema change ships with a migration and a rollback.
- Before touching infra, read the terraform plan end to end.
MD
cat > "$L/profiles/researcher.md" <<'MD'
---
name: Researcher
description: Sourced answers, clear charts
skills:
  - deep-research
  - data-viz
order: 30
---
## Researcher

- Use primary sources and link every claim.
- Say what is unknown instead of guessing.
MD

# --- Projects ---
for p in acme-web payments-api; do mkdir -p "$H/work/$p/.git/info" && printf '# git ls-files --others --exclude-from=.git/info/exclude\n' > "$H/work/$p/.git/info/exclude"; done
printf '# acme-web\n\nNext.js 16 app. Run `pnpm test` before pushing.\n' > "$H/work/acme-web/CLAUDE.md"
printf '# payments-api\n\nGo service. `make test` must pass.\n' > "$H/work/payments-api/AGENTS.md"

# --- Real assignments, applied through the CLI (gives links, profile blocks and history) ---
swift build --product kitfold >/dev/null
KF="$(swift build --show-bin-path)/kitfold"
k() { "$KF" --home "$H" --no-color "$@" >/dev/null; }
k assign code-review '*' --yes
k assign release-notes claude-code --yes
k assign release-notes codex --yes
k assign k8s-debug codex --yes
k profile code-reviewer claude-code --yes
k profile backend-engineer codex --project "$H/work/payments-api" --yes
k assign design-tokens claude-code --project "$H/work/acme-web" --yes
k assign figma-handoff opencode --project "$H/work/acme-web" --yes
echo "Demo home ready: $H"
