## What and why

<!-- What does this change, and why? Link the issue if there is one. -->

## How it was tested

<!-- Tests added or updated; manual checks in a sandbox home; screenshots for UI changes. -->

## Checklist

- [ ] `make test` passes, and `make lint` is clean
- [ ] Nothing in tests or manual checks wrote to a real `$HOME` (FakeHome, `--home`, `KITFOLD_FAKE_HOME`, `KITFOLD_HOME`)
- [ ] Every file change goes through Planner → Plan → Executor (preview, preconditions, undo)
- [ ] New agent behavior has a source in `docs/research.md`, and assumptions are marked `verified: false`
- [ ] User-visible changes are noted under **Unreleased** in `CHANGELOG.md`
- [ ] UI changes include before/after screenshots (`KITFOLD_SNAPSHOT_DIR`)
