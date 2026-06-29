# Bugu / 布谷

Bugu is a small macOS menu bar app for long-running local coding agents. The
Chinese name is `布谷`: a tiny coding clock that chirps when a task is accepted,
keeps a quiet heartbeat while work continues, and calls back with a different
sound when the task changes state.

MVP behavior:

- Starts macOS IOKit power assertions to reduce sleep interruptions.
- Plays short state cues at a user-controlled alert volume.
- Separates five task states: accepted, running, completed, interrupted, and
  permission needed.
- Uses familiar Apple system sounds for all five states so they are easier to
  distinguish without learning a new sound language.
- Supports heartbeat intervals: 10s, 30s, 1m, 5m, 10m, and 30m.
- Watches common local coding agent processes and chirps when a new session
  starts.
- Does not use voice/TTS by default, so headphone disconnects do not turn status
  updates into loud spoken alerts.

The default sound direction uses macOS built-in alert sounds: short, clear,
event-specific cues that do not steal focus. Bugu also ships the optional
"Bugu Pack" — five original, hand-picked sounds provided by the project — for
users who want a warmer, more recognizable set of state cues. Bugu does not
copy Vibe Island or Claude audio, or use voice/TTS.

## Status Sounds

Two sound packs are included. The default uses macOS built-in alert sounds; the
"Bugu Pack" uses original MP3 cues provided by the project. You can switch
between them from the menu bar window.

| State | Meaning | System Sound | Bugu Pack |
| --- | --- | --- | --- |
| Accepted | A new coding agent task was detected | Funk | start |
| Running | The watched task is still active | Hero | continue |
| Completed | The watched task ended normally | Blow | success |
| Interrupted | The watched task stopped unexpectedly | Basso | end |
| Permission needed | The task needs user approval | Ping | need |

All five cues are played once via `NSSound`. The System pack uses built-in
sound names; the Bugu Pack loads `*.mp3` files bundled in the app.

The `Alert volume` slider applies to all five states. It defaults to 65%, can be
set from 20% to 100%, and is saved between launches.

The app icon is generated from an original local drawing script:

```bash
python3 script/generate_app_icon.py
```

Closed-lid force-awake behavior is intentionally not enabled in the MVP. It can
increase heat and battery risk, and usually needs a separate privileged `pmset`
or helper-tool path, so it should be added later as an explicit experimental
mode with clear safety copy.

## Run

```bash
./script/build_and_run.sh
```

Verify process launch:

```bash
./script/build_and_run.sh --verify
```

Scan currently visible coding agents:

```bash
$(swift build --show-bin-path)/CodeBeacon --scan-agents
```

## Download a Community Build

Bugu can be distributed as an unsigned community build before we add an Apple
Developer ID certificate and notarization credentials. This keeps release costs
at 0 USD, but macOS Gatekeeper will warn that the developer cannot be verified.

Build the unsigned DMG:

```bash
./script/release.sh --skip-notarization 0.1.1-community
```

The DMG is written to:

```bash
dist/Bugu-0.1.1-community.dmg
```

To open the app after downloading:

1. Mount the DMG and drag `Bugu.app` to `Applications`.
2. Control-click or right-click `Bugu.app`, then choose `Open`.
3. Confirm `Open` in the macOS security dialog.

If macOS still blocks the app, open `System Settings` -> `Privacy & Security`
and choose `Open Anyway` for Bugu. Advanced users can also remove the download
quarantine flag after verifying the source:

```bash
xattr -dr com.apple.quarantine /Applications/Bugu.app
```

Release-ready DMGs for broader distribution should be signed with a real
`Developer ID Application` certificate and notarized with `notarytool`.

## Current Prototype Flow

1. Open the menu bar item.
2. Toggle `Keep Mac awake`.
3. Toggle `Watch coding agents`.
4. Set `Alert volume`.
5. Pick a heartbeat interval.
6. Start a supported agent process.
7. Wait for heartbeat audio.
8. Let the watched agent process exit to hear the completion cue.
9. Uncheck `Watch coding agents` to stop watching and clear the current task
   heartbeat.

`Sim Agent`, `Sim Interrupt`, and `Reset watcher` live in the Debug section.
They test automatic detection and forced watcher cleanup without adding extra
controls to the normal user flow.

## Apple System Sounds

macOS built-in alert sounds live at:

```bash
/System/Library/Sounds
```

List them:

```bash
find /System/Library/Sounds -maxdepth 1 -type f -name '*.aiff' -print | sort
```

Preview one:

```bash
afplay /System/Library/Sounds/Hero.aiff
```

Open the folder in Finder:

```bash
open /System/Library/Sounds
```

## Watched Agents

The MVP watches process names/commands for:

- Codex
- Claude Code
- OpenCode
- Aider
- Goose
- Gemini CLI
- Amp
- Qwen Code
- Crush
- Devin
- Cursor Agent
- OpenHands

It intentionally ignores noisy desktop helper processes from `Codex.app` and
`Claude.app` so renderer/helper restarts do not count as new coding tasks.
