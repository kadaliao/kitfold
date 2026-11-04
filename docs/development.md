# Development guide

## Requirements

- macOS 15 or later
- Xcode 26 or later (Swift 6.2+). CI builds with Swift 6.2.
- No third-party packages. KitfoldCore uses Foundation, CryptoKit and the system `libsqlite3`.

## Everyday commands

| Command | What it does |
|---|---|
| `make build` | Debug build of the core, CLI and app |
| `make test` | Run all tests (each in its own temporary home) |
| `make run` | Launch the app from the build folder |
| `make cli ARGS="status"` | Run the CLI, e.g. `make cli ARGS="skills --no-color"` |
| `make app` | Release build in `build/Kitfold.app` (with icon and bundled CLI) |
| `make demo DIR=/tmp/kf` | Build the fictional demo home |
| `make screenshots` | Regenerate release screenshots |
| `make video` | Render the launch video and GIFs, e.g. `make video MUSIC=~/music.mp3` |
| `make format` | Format sources with `swift format` |
| `make clean` | Remove `.build` and `build` |

## Environment variables

| Variable | Effect |
|---|---|
| `KITFOLD_HOME=<dir>` | Where Kitfold keeps its own data (config, state DB, backups, library). Default `~/.kitfold`. Use it to inspect your real agents read-only without creating `~/.kitfold`. |
| `KITFOLD_FAKE_HOME=<dir>` | Treat `<dir>` as `$HOME`: agent folders, Kitfold's data, everything. `CODEX_HOME`, `CLAUDE_CONFIG_DIR` and similar are ignored unless they point inside it. The CLI's `--home <dir>` does the same. |
| `CLAUDE_CONFIG_DIR`, `CODEX_HOME` | Honored like the agents themselves honor them. |
| `KITFOLD_SNAPSHOT_DIR=<dir>` | App only: render pages to PNGs, then quit (see below). |
| `KITFOLD_SNAPSHOT_SCRIPT=marketing\|video` | Use the release-screenshot or launch-video sequence instead of the page tour. `video` applies its change, but only inside a fake home. |
| `KITFOLD_SNAPSHOT_APPEARANCE=light\|dark` | Force an appearance for snapshots. |
| `KITFOLD_SNAPSHOT_SIZE=1440x900` | Window size in points for snapshots. |

## Testing

Tests use [Swift Testing](https://developer.apple.com/documentation/testing). `FakeHome` (`Tests/KitfoldCoreTests/Support.swift`) creates an isolated `$HOME` with helpers to lay out skills, links and files, and `Workspace.assign(…)` applies a rule end to end. A good test usually:

1. lays out a realistic home (shared skills, links from other tools, a hand-made folder…);
2. changes a rule and applies the plan;
3. asserts what changed **and what did not** (foreign links, user content, other agents);
4. undoes, and asserts the original state is back.

Please keep the end-to-end tests fast. The whole suite runs in well under a second.

## Trying changes safely

```bash
scripts/demo/make-demo-home.sh /tmp/kf-demo     # fictional agents, skills, profiles, projects, history
.build/debug/kitfold --home /tmp/kf-demo status
KITFOLD_FAKE_HOME=/tmp/kf-demo PATH=/tmp/kf-demo/.local/bin:/usr/bin:/bin .build/debug/KitfoldApp
```

The demo home has stand-in agent binaries that only answer `--version`, so all four agents show as installed.

Checking your real machine read-only:

```bash
KITFOLD_HOME=/tmp/kf-scratch .build/debug/kitfold status
KITFOLD_HOME=/tmp/kf-scratch .build/debug/kitfold skills --no-color
```

Comparing against an agent's own view is the best check of an adapter. For example, `opencode debug skill` prints OpenCode's skill list as JSON.

## Checking the UI

macOS may block screen capture for terminal-launched tools. The app can render its own window instead:

```bash
KITFOLD_SNAPSHOT_DIR=/tmp/shots KITFOLD_HOME=/tmp/kf-scratch swift run KitfoldApp   # every page once
ls /tmp/shots
```

Snapshot mode makes draft changes only for the review sheet and never applies them (except the `video` script, and only in a fake home). `scripts/lib/snapshot-app.sh` wraps the binary in a throwaway `.app` and runs one snapshot script against a demo home.

`scripts/screenshots/make.sh` builds the demo home, captures dark and light sets, and frames them with `scripts/screenshots/frame.swift`:
- full-size PNGs go to `build/screenshots/`;
- README JPEGs go to `docs/assets/screenshots/`.

## Launch video

`scripts/video/make.sh [music.mp3]` renders the launch video from the demo home. It needs Google Chrome, Node 22+ and ffmpeg.
1. The app's `video` snapshot script captures the states the story needs. It also exports the agents' logos as transparent PNGs.
2. `scripts/video/scene.html` is the whole video as one deterministic timeline: `seek(t)` places every element.
3. `scripts/video/render.mjs` steps through it in headless Chrome, using the DevTools protocol over Node's built-in WebSocket, and pipes the frames into ffmpeg.

The first frame is the title card. Output goes to `build/video/`:
- `kitfold-launch.mp4` (1080p60) and a smaller `kitfold-launch-small.mp4`;
- `kitfold-launch.gif` (the whole video);
- `kitfold-demo.gif` (the short cut used in the README; copy it to `docs/assets/` when it changes).

To check one moment, render a single frame: `node scripts/video/render.mjs --assets <dir> --still 29.5 --out frame.png`. Music isn't in the repository. The published cut uses "Focus on Yourself" by Eugenio Mininni, under the Mixkit Stock Music Free License.

## Release build

```bash
make app            # build/Kitfold.app, ad-hoc signed
```

`scripts/bundle.sh` builds release binaries, draws the icon (`scripts/make-icon.swift`), writes `Info.plist` and copies the CLI into `Contents/Resources/kitfold`. Signing with a Developer ID, notarization and updates are on the [roadmap](roadmap.md).

## Where things are

| You want to… | Look at |
|---|---|
| change how an agent is detected or where it looks | `Sources/KitfoldCore/Adapters/BuiltinAgents.swift` |
| read an agent's own disable settings | `Adapters/NativePolicy.swift` |
| write them (target files, entries, Codex's managed section) | `Adapters/NativeSettings.swift`, `Sync/NativePlanner.swift`, `Support/JSONEdit.swift` |
| change an agent's logo | `Sources/KitfoldApp/AgentLogos.swift` |
| change what counts as loaded / health checks | `Scan/Scanner.swift`, `Scan/Snapshot.swift`, `Scan/Diagnostics.swift` |
| change what gets written | `Sync/Planner.swift`, `Sync/ManagedBlock.swift` |
| change how it gets written / undone | `Sync/Executor.swift`, `State/StateStore.swift` |
| add a CLI command | `Sources/kitfold/main.swift` |
| change app state or a page | `Sources/KitfoldApp/AppModel.swift` and the `*View.swift` files |
