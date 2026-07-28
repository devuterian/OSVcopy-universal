# OSVcopy Spec

This file is the canonical statement of what OSVcopy is supposed to be.  
Keep it durable. Do not use it as a changelog, inbox, or weekly narrative.

- **Project:** OSVcopy
- **Canonical repo:** https://github.com/devuterian/osvcopy-universal
- **Project id:** `osvcopy-universal`
- **Operator:** repository maintainers (see GitHub owners)
- **Last updated:** 2026-07-28
- **Related decisions:** (none filed yet)

## Project thesis

Give **DJI Osmo 360** and **Insta360 X series** (and similar) users a **native desktop** way on macOS and Windows to **import and file** footage and stills by **capture date** into predictable library folders, without replacing Lightroom or manufacturer desktop apps.

## Primary user context

Photographers and videographers who keep a **disk or NAS library** (often SMB) and want **YYYY-MM-DD** (or nested `YYYY/YYYY-MM-DD`) layout, with **safe dedupe** when the same file appears again.

## Core capabilities

- Recursive discovery of media under dropped paths or folders.
- Date resolution: filename patterns → optional `ffprobe` metadata → file timestamps.
- Copy or move into user-chosen **library root** with chosen folder layout.
- Skip duplicates when an existing file matches the selected duplicate check mode: **same MD5** by default, or **same file size only** when the operator chooses the faster size-only mode.
- Progress in UI and Dock or Windows taskbar; optional completion notification.

## Invariants

- **User-chosen destination** is explicit; the app does not silently pick a cloud or system folder.
- **Destructive operations** (move, overwrite policy) must remain visible in the UI and documented in `README.md`.
- **No network upload** to third parties as part of core product behavior.

## Non-goals

- RAW development, timeline editing, or catalog database replacement (not Lightroom).
- Linux packaging and browser-only file organization.

## Main surfaces

- SwiftUI app target `OSVcopy` in SwiftPM package for macOS.
- Electron package under `desktop/` for Windows.
- Release distribution: unsigned `.dmg` and unsigned Windows installer artifacts until signing is configured.

## Success criteria

- Reliable import for **`.OSV`** and **`.INSV`** alongside common image/video types.
- Predictable folder output and **clear operator feedback** on skips and errors.
