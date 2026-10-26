# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Documentation

- README: a Demo section with a real recording that uses made-up content, a social preview image, a
  Download button, and a "Before you install" note.
- Privacy wording corrected in README, SECURITY.md and CONTRIBUTING.md. The extension reads
  ChatGPT's page locally to display it: navigation, titles, the model name, the displayed
  conversation for Find/Word count/Print/Download, and the clipboard on Paste. It stores view
  preferences in chatgpt.com's `localStorage`, declares no Chrome API permissions, and makes no
  network requests of its own. The earlier wording ("never reads conversations", "no permissions",
  "permission-free") was imprecise. The extension's behavior did not change.
- Still to update in the next release (program files, unchanged here): the manifest description
  ("No permissions"), the header comment in `docmode.js` ("localStorage, this window only"), the
  installer's extension message in `Build-Installer.ps1` ("no permissions"), and the README copy
  bundled in the installer.

## [2.0.4] - 2026-10-26

First public release.

### Added

- Controller (AutoHotkey v2) with five global hotkeys: show/hide (`Ctrl+Alt+G`), opacity up/down
  (`Ctrl+Alt+Up`/`Down`, 5 % steps, 1 % floor), always-on-top (`Ctrl+Alt+T`) and emergency reset
  (`Ctrl+Alt+Shift+R`, temporary 100 % that never overwrites the saved opacity).
- Document Workspace: chatgpt.com in a Chrome app window, styled by a Manifest V3 extension with no
  Chrome API permissions as an original document editor (menus, toolbar, chat tabs, ruler, page widths, compact
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
