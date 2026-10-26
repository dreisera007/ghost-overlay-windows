# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.0.4] - 2026-10-26

First public release.

### Added

- Controller (AutoHotkey v2) with five global hotkeys: show/hide (`Ctrl+Alt+G`), opacity up/down
  (`Ctrl+Alt+Up`/`Down`, 5 % steps, 1 % floor), always-on-top (`Ctrl+Alt+T`) and emergency reset
  (`Ctrl+Alt+Shift+R`, temporary 100 % that never overwrites the saved opacity).
- Document Workspace: chatgpt.com in a Chrome app window, styled by a permission-free Manifest V3
  extension as an original document editor (menus, toolbar, chat tabs, ruler, page widths, compact
  layout for small overlays).
- Native fallback for the official ChatGPT Windows app, and `Switch-Mode.cmd` to switch between the two.
- Optional per-user Startup shortcut that prepares the window hidden at sign-in.
- Single-file installer with upgrade-in-place (keeps your settings) and `-Uninstall`.
- `GhostOverlay.log` records every saved opacity change, so unexpected changes can be traced.

### Fixed

- Chats inside ChatGPT Projects could render in a narrow column of about 300 px. ChatGPT keeps the
  previously visited page mounted but hidden, and the workspace measured that hidden copy. It now
  always measures the copy on screen, for both "Fit page to window" and fixed page widths.
- The controller could attach to a different chatgpt.com app window after a restart. It now accepts
  only the exact app identity Chrome derives from the configured start page and profile (long
  addresses included), and always prefers the window it used last.

[Unreleased]: https://github.com/dreisera007/ghost-overlay-windows/compare/v2.0.4...HEAD
[2.0.4]: https://github.com/dreisera007/ghost-overlay-windows/releases/tag/v2.0.4
