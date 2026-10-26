# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.1.0] - 2026-10-26

### Added

- Click-to-rename: click the chat title in the Document Workspace header to rename the real ChatGPT
  conversation. Enter saves, Escape cancels, clicking elsewhere saves a changed title, and empty titles
  are refused. A pencil appears on hover. The rename goes through ChatGPT's own Rename dialog for the
  conversation in the address bar (never chosen by title, so duplicate titles are safe). Success is only
  reported once ChatGPT shows the new title; otherwise the real title comes back or ChatGPT's dialog is
  shown. Works in ordinary and Project chats; disabled with an explanation in temporary and unsaved
  chats; leaving the chat while typing cancels.
- Header, chat tabs and the Chats menu show a confirmed new title at once, even while ChatGPT's own
  chat list lags behind. A newer title shown by ChatGPT (renamed elsewhere) always takes precedence.
- Opacity diagnostics: each "opacity saved" log line also records how many Ctrl+Alt+Up/Down presses
  caused it, whether Ctrl and Alt were physically held (keys sent by software aren't; AltGr shows as
  right Alt with left Ctrl), and the program in front. No other keys or text are recorded.

### Changed

- The periodic header refresh no longer overwrites the title while you type or while a rename saves.
- Wording corrected in program files: the extension's manifest description, the header comment in
  `docmode.js`, and the installer's message about the extension (no Chrome API permissions; runs only
  on chatgpt.com).
- `Build-Installer.ps1` takes `-OutFile` to write the installer to another folder.

### Known issues

- The Projects menu lists no projects since a ChatGPT navigation change (also in 2.0.4).

### Documentation

- README: a Demo section with a real recording that uses made-up content, a social preview image, a
  Download button, and a "Before you install" note.
- New "Installation report" issue form for testers: what worked, which steps were confusing, the
  hotkeys, and the time taken. Only the outcome and a privacy check are required.
- Privacy wording corrected in README, SECURITY.md and CONTRIBUTING.md. The extension reads
  ChatGPT's page locally to display it: navigation, titles, the model name, the displayed
  conversation for Find/Word count/Print/Download, and the clipboard on Paste. It stores view
  preferences in chatgpt.com's `localStorage`, declares no Chrome API permissions, and makes no
  network requests of its own. The earlier wording ("never reads conversations", "no permissions",
  "permission-free") was imprecise. The extension's behavior did not change.
- The program-file wording listed here for the next release (manifest description, `docmode.js`
  header comment, installer message, bundled README) is corrected in 2.1.0.

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

[Unreleased]: https://github.com/dreisera007/ghost-overlay-windows/compare/v2.1.0...HEAD
[2.1.0]: https://github.com/dreisera007/ghost-overlay-windows/compare/v2.0.4...v2.1.0
[2.0.4]: https://github.com/dreisera007/ghost-overlay-windows/releases/tag/v2.0.4
