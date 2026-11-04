# Contributing to Kitfold

Thanks for helping! This guide covers what you need to make a good pull request.

## Ground rule: never touch a real `$HOME`

Kitfold edits other programs' configuration. Development must never do that by accident.

- **Tests** build a throwaway home under a temp dir (`FakeHome` in `Tests/KitfoldCoreTests/Support.swift`). Never use `NSHomeDirectory()` or `KitfoldEnvironment.current()` in tests.
- **Manual write tests** (apply, undo) go through a sandbox: `kitfold --home <dir>` or `KITFOLD_FAKE_HOME=<dir>`. `scripts/demo/make-demo-home.sh <dir>` builds a realistic one.
- **Read-only checks against your machine** set `KITFOLD_HOME=<scratch dir>`, so not even `~/.kitfold` gets created.
- **Agent config files can hold secrets** (API keys in `env` blocks, tokens). Code that reads them must take only the keys it needs, and must never log, print or store anything else. Don't paste these files into issues.

## Setup

Requirements: macOS 15+, Xcode 26+ (Swift 6.2+). No third-party dependencies.

```bash
make build      # all targets
make test       # unit + end-to-end tests (sandboxed)
make run        # launch the app
make app        # build/Kitfold.app (release)
```

See [docs/development.md](docs/development.md) for environment variables, the demo home and screenshots.

## Project layout

| Path | What lives there |
|---|---|
| `Sources/KitfoldCore` | All logic: models, agent adapters, scanning, planning, executing, journal. Foundation + SQLite only, built under Swift 6 strict concurrency. |
| `Sources/kitfold` | CLI front end |
| `Sources/KitfoldApp` | SwiftUI app (`AppModel` + views) |
| `Tests/KitfoldCoreTests` | Swift Testing suites |
| `scripts/` | Bundling, icon, demo home, screenshots |
| `docs/` | Development guides (English) and design docs (Chinese) |

## Making changes

- **Behavior lives in `KitfoldCore`.** The app and CLI stay thin. If you need logic in a view, it probably belongs in the core.
- **Agent differences live in descriptors** (`Adapters/BuiltinAgents.swift`), not in `if agent == …` branches. See [docs/adding-an-agent.md](docs/adding-an-agent.md).
- **Every file change goes through `Planner` → `Plan` → `Executor`.** Don't write to agent files directly; that's what keeps preview, preconditions, backups and undo honest.
- **Claims about agent behavior need a source.** Mark descriptor entries `verified: false` when you're inferring, and update [docs/research.md](docs/research.md) with the evidence (docs URL, source file at a version tag, or a reproducible sandbox test).
- **Add tests** for new behavior, especially safety properties: what must *not* change, preconditions, undo.
- **UI changes:** check them with `KITFOLD_SNAPSHOT_DIR` (renders every page to PNG) and include before/after images in the PR.

### Style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/). 4-space indent, ~140-column lines (see `.editorconfig`).
- Comments explain *why*, not *what*.
- User-facing text is short and plain. Say what will happen and what to do about it.

### Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Keep a PR to one topic and fill in the template.
- Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.
- CI must pass (`swift build` + `swift test` on macOS).

## Reporting bugs and requesting agents

Use the issue templates. If you attach `kitfold status` output, review it first: it shows paths under your home folder.

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
