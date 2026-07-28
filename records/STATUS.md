# OSVcopy Status

Current accepted operational reality for this repo.

## Snapshot

- **Last updated:** 2026-07-28
- **Overall posture:** `active`
- **Current focus:** Stabilize the Windows Electron desktop MVP while retaining the SwiftUI macOS app.
- **Highest-priority blocker:** Windows packaging and runtime smoke tests have not yet run in a Windows environment.
- **Next operator decision needed:** signing strategy for macOS and Windows releases.
- **Related decisions:** none

## Current State Summary

**OSVcopy 1.0.0** remains available as a macOS DMG. The repository now also contains an Electron-based Windows MVP under `desktop/`, with Windows installer generation defined in GitHub Actions. Repository operations continue to follow repo-template.

## Active Phases Or Tracks

### Template adoption

- **Goal:** Match LPFchan/repo-template scaffold (policy, hooks, skills, workflows).
- **Status:** `in progress`
- **Why this matters now:** Single operator + agents need a shared contract for commits and artifacts.
- **Current work:** Land scaffold files; migration commit; policy in `records/REPO.md` only.
- **Exit criteria:** Hooks installed by default for contributors who run `install-hooks.sh`; CI green on `main`.
- **Dependencies:** none
- **Risks:** Contributors unfamiliar with `LOG-*` commits; mitigated via `records/REPO.md` and `skills/commit-generator/SKILL.md`.
- **Related ids:** none


### Windows Electron MVP

- **Goal:** Provide the import and date-based filing workflow on Windows 10/11.
- **Status:** `implemented, awaiting Windows CI validation`
- **Current work:** Recursive scan, copy/move, MD5 dedupe, taskbar progress, native dialogs, restricted preload IPC, and installer workflow.
- **Exit criteria:** Windows workflow passes and the generated installer completes a smoke test on Windows.
- **Risks:** Unsigned installer warnings; image EXIF date extraction is not yet implemented in Electron.
- **Related ids:** DEC-20260728-001

## Recent Changes To Project Reality

- 2026-05-02
  - **Change:** Open-sourced app; added GitHub Actions Swift CI; released DMG 1.0.0.
  - **Why it matters:** Establishes public baseline for issues and PRs.
  - **Related ids:** none

## Active Blockers And Risks

- **Risk:** Unsigned macOS binaries may trigger Gatekeeper friction.
  - **Effect:** Support burden; users must follow README security steps.
  - **Owner:** operator
  - **Mitigation:** Document clearly; consider notarization in `PLANS.md`.
  - **Related ids:** none

## Immediate Next Steps

- **Next:** Confirm `commit-standards` and `ci` workflows pass on `main` after template merge.
  - **Owner:** operator / agents with push access
  - **Trigger:** post-merge CI run
  - **Related ids:** none
