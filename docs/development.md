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
| `make tutorial-shots` | Regenerate the tutorials' screenshots, in English and Chinese |
| `make video` | Render the launch video and GIFs, e.g. `make video VARIANTS="en zh zh-portrait" MUSIC=~/music.mp3` |
| `make format` | Format sources with `swift format` |
| `make clean` | Remove `.build` and `build` |

## Environment variables

| Variable | Effect |
|---|---|
| `KITFOLD_HOME=<dir>` | Where Kitfold keeps its own data (config, state DB, backups, library). Default `~/.kitfold`. Use it to inspect your real agents read-only without creating `~/.kitfold`. |
| `KITFOLD_FAKE_HOME=<dir>` | Treat `<dir>` as `$HOME`: agent folders, Kitfold's data, everything. `CODEX_HOME`, `CLAUDE_CONFIG_DIR` and similar are ignored unless they point inside it. The CLI's `--home <dir>` does the same. |
| `CLAUDE_CONFIG_DIR`, `CODEX_HOME` | Honored like the agents themselves honor them. |
| `KITFOLD_LANG=en\|zh-Hans` | Language of the app and CLI, instead of the system's. See [localization.md](localization.md). |
| `KITFOLD_SNAPSHOT_DIR=<dir>` | App only: render pages to PNGs, then quit (see below). |
| `KITFOLD_SNAPSHOT_SCRIPT=marketing\|video\|tutorial\|language` | Use the release-screenshot, launch-video or tutorial sequence instead of the page tour. `video` applies its change, but only inside a fake home. `language` switches language while running and writes the menu bar to text files, to check that everything follows. |
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

`scripts/lib/snapshot-app.sh` renders in English unless `KITFOLD_LANG=zh-Hans` is set; it also passes `-AppleLanguages` so macOS's own controls match.

`scripts/tutorials/make.sh` builds a demo home per language (its history is written in that language too) and saves the tutorial screenshots to `docs/tutorials/images/en/` and `docs/tutorials/images/zh-CN/`.

`scripts/screenshots/make.sh` builds the demo home, captures dark and light sets, and frames them with `scripts/screenshots/frame.swift`:
- full-size PNGs go to `build/screenshots/`;
- README JPEGs go to `docs/assets/screenshots/`.

`scripts/screenshots/make.sh zh-Hans` renders the Chinese set for `README.zh-CN.md` into `docs/assets/screenshots/zh-CN/`; pass `en zh-Hans` for both.

## Launch video

`scripts/video/make.sh [variant ...]` renders the launch video from the demo home. Variants are `en`, `zh`, `en-portrait` and `zh-portrait` (1080×1920); the default is `en`. It needs Google Chrome, Node 22+ and ffmpeg.
1. The app's `video` snapshot script captures the states the story needs. It also exports the agents' logos as transparent PNGs.
2. `scripts/video/voice.mjs` speaks each scene's line from `narration.json` with Gemini TTS (`gemini-3.8-flash-lite-tts`). Each scene then stretches to fit its line. The script also writes subtitles. Clips are cached in `build/video/voice/`, so a re-run only pays for lines that changed.
3. `scripts/video/scene.html` is the whole video as one deterministic timeline: `seek(t)` places every element. Query parameters pick the language, the layout and the narration timeline.
4. `scripts/video/render.mjs` steps through it in headless Chrome, using the DevTools protocol over Node's built-in WebSocket, and pipes the frames into ffmpeg.
5. `scripts/video/mix.mjs` lays the narration at -16 LUFS over the music, which dips while the narrator speaks.

Narration needs `GEMINI_API_KEY`, or `AIHUBMIX_API_KEY` for AIHubMix's Gemini-compatible endpoint (set `AIHUBMIX_IP` if your DNS resolves that host badly). `VOICE=0` renders without narration.

The first frame is the title card. Output goes to `build/video/`:
- `kitfold-launch-<variant>.mp4` (60 fps) and a smaller `kitfold-launch-<variant>-small.mp4`;
- `kitfold-launch-<variant>.srt`, the narration's subtitles (portrait variants also have them burned in);
- with `en`: `kitfold-launch.gif` (the whole video) and `kitfold-demo.gif` (the short cut used in the README; copy it to `docs/assets/` when it changes).

To check one moment, render a single frame: `node scripts/video/render.mjs --assets <dir> --still 29.5 --out frame.png`, adding e.g. `--size 1080x1920 --query "lang=zh&layout=portrait"`. Music isn't in the repository. The published cut uses "Focus on Yourself" by Eugenio Mininni, under the Mixkit Stock Music Free License.

## Release build

```bash
make app            # build/Kitfold.app, ad-hoc signed
```

`scripts/bundle.sh` builds release binaries, draws the icon (`scripts/make-icon.swift`), writes `Info.plist` and copies the CLI into `Contents/Resources/kitfold`. `ARCHS="arm64 x86_64"` makes it universal.

## Releasing

A release is a universal `Kitfold-<version>.dmg` on GitHub Releases, signed with a Developer ID and notarized.

One-time setup: a **Developer ID Application** certificate in the login keychain (the script uses `Developer ID Application: Xingyi Liao (HMDAVG9B8J)`; set `SIGN_IDENTITY` for another), and a notarytool keychain profile:

```bash
xcrun notarytool store-credentials notary --apple-id <apple-id> --team-id <team-id>
```

It asks for an app-specific password and keeps everything in the keychain. Never commit credentials.

1. **Version.** Set `VERSION` in `scripts/bundle.sh` and add 1 to `BUILD`. Tags are `v<version>`.
2. **Changelog.** Move the Unreleased entries under `## [<version>] - <date>` and update the links at the bottom.
3. **Test:** `make test` and `make lint`.
4. **Build:** `NOTARY_PROFILE=notary make release`. It builds the universal app, signs the app and its CLI with the hardened runtime and a secure timestamp, notarizes and staples it, checks it with `spctl`, then builds, signs, notarizes and staples the disk image. Output: `build/release/Kitfold-<version>.dmg` and `SHA256SUMS`. Without `NOTARY_PROFILE` everything is signed but not notarized; don't publish that. If Apple rejects it, `xcrun notarytool log <id> --keychain-profile notary` says why.
5. **Smoke test:** open the disk image, drag Kitfold to Applications, open it (no Gatekeeper warning), check the version in About.
6. **Commit, tag, publish:**

   ```bash
   git commit -am "Release <version>" && git tag -a v<version> -m "Kitfold <version>"
   git push origin main --tags
   gh release create v<version> build/release/Kitfold-<version>.dmg build/release/SHA256SUMS \
     --title "Kitfold <version>" --notes-file <notes.md>
   ```

   Notes: the install line first, in English and Chinese, then the changes.

   The app and `kitfold update` update from the latest GitHub release: they look for the tag `v<version>` and the assets `Kitfold-<version>.dmg` and `SHA256SUMS` under exactly those names, and install the disk image only if it's signed by the same Developer ID team and notarized. So keep the names, and don't publish an unnotarized image as the latest release (it would be refused, and every user would see the update fail). The release notes are what the update sheet shows.

## Where things are

| You want to… | Look at |
|---|---|
| change how an agent is detected or where it looks | `Sources/KitfoldCore/Adapters/BuiltinAgents.swift` (the four in depth), `AgentCatalog+Specs.swift` (the rest) |
| change how unknown agents are found | `Adapters/AgentDiscovery.swift` |
| read an agent's own disable settings | `Adapters/NativePolicy.swift` |
| write them (target files, entries, Codex's managed section) | `Adapters/NativeSettings.swift`, `Sync/NativePlanner.swift`, `Support/JSONEdit.swift` |
| change an agent's logo | `Sources/KitfoldApp/AgentLogos.swift` |
| change what counts as loaded / health checks | `Scan/Scanner.swift`, `Scan/Snapshot.swift`, `Scan/Diagnostics.swift` |
| change what gets written | `Sync/Planner.swift`, `Sync/ManagedBlock.swift` |
| change how it gets written / undone | `Sync/Executor.swift`, `State/StateStore.swift` |
| add a CLI command | `Sources/kitfold/main.swift` |
| add or change a message | the `L("…")` at the call site and `Sources/KitfoldCore/Localization/` ([localization.md](localization.md)) |
| change app state or a page | `Sources/KitfoldApp/AppModel.swift` and the `*View.swift` files |
