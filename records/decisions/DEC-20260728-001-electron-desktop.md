# DEC-20260728-001: Electron desktop for Windows support

Opened: 2026-07-28 00-00-00 KST
Recorded by agent: chatgpt-gpt56

## Decision

Keep the existing SwiftUI macOS application and add an isolated Electron desktop package under `desktop/` for Windows support.

## Rationale

The product requires recursive filesystem access, large local file transfers, hashing, subprocess execution for `ffprobe`, cancellation cleanup, native folder dialogs, notifications, and taskbar progress. A GitHub Pages runtime cannot provide these capabilities reliably. A static site may later document and distribute releases, but it will not host the privileged application renderer.

## Constraints

- Electron renderer loads only packaged local files.
- Node integration remains disabled and context isolation plus sandboxing remain enabled.
- Native capabilities are exposed through a narrow preload API.
- Long-running scan and transfer work runs in an Electron utility process.
- Existing Swift source remains available for the macOS application.
