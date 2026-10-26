# What has been tested

Every automated test drives the real hotkeys and inspects the real windows. Test runs used only
synthetic content: temporary chats, a dedicated test chat and a dedicated test Project. The checks
read no conversation or project titles.

Test machine: Windows 11 Home (build 26200) at 150 % display scaling, AutoHotkey 2.0.23,
Google Chrome 155, ChatGPT Store app `OpenAI.Codex` 26.1021. One monitor.

## Release 2.0.4 (controller with exact window identity, extension 2.0.4)

| Test | Result |
|---|---|
| Project-chat page width, measured after in-app navigation (a hidden copy of the previous page present), Wide and "Fit page to window" at 1536 × 900, 800 × 600 and 430 × 550 | PASS: page 1080 / 920 / 780 / 410 px, no horizontal scrolling. The previous logic gave 280 px in every Project case |
| Same for an ordinary chat, navigating both directions | PASS |
| Window identity: exact app ID accepted; deep-link, other profile, ordinary Chrome and look-alike host IDs rejected; a deep-link start page produces Chrome's real shortened ID | PASS |
| A second window with the **same** app ID open: controller restarted via the Startup shortcut keeps to its own window and leaves the other untouched | PASS |
| Targeted regression: show/hide, focus return, move/resize kept, opacity 25 % ↔ 30 %, emergency reset (temporary 100 %, saved value kept), always-on-top both ways, second copy refused, native fallback and back (native window returned exactly), Startup shortcut → prepared hidden at 30 % | 30/32 PASS. The two failures were in the test's process counter, not the product: the log shows exactly one controller after each mode switch |
| Real Project conversation checked by hand by the maintainer | PASS |
| Installer for this release: see the release notes for the isolated install test | — |

## Earlier verification (same features, previous builds)

These ran on earlier 2.0.x builds. The features are unchanged in 2.0.4 apart from the fixes above.

| Test | Result |
|---|---|
| `Test-GhostOverlay.ahk Document`: all five hotkeys, opacity levels (30 % = alpha 77, 10 % = 26, 1 % = 3, 100 % opaque), 1 % floor, emergency reset from 1 % + off-screen, focus return, watchdog, controller crash/restart, single instance, idle CPU/RAM, stop restores the window | 58/58 PASS |
| Ordinary Chrome windows during the whole suite (opacity and topmost before/after) | Unchanged |
| `Test-Startup.ahk Document` and `ChatGPT`: real Startup shortcut, window prepared hidden, no visible flash, first `Ctrl+Alt+G` < 100 ms | 15/15 PASS each |
| `Test-GhostOverlay.ahk ChatGPT` (native app) | 50/50 PASS |
| All five hotkeys on a physical keyboard (native mode) | PASS |
| Rapid key presses (double-tapped `Ctrl+Alt+G`, 14-press opacity bursts) | No presses lost |
| Installer: fresh install, upgrade keeping settings, `-Mode`, `-Uninstall`; an existing Startup shortcut of another copy left byte-identical | PASS |
| Ordinary Chrome tab: no workspace, ChatGPT's own layout | PASS |
| Workspace menus and toolbar: formatting, undo/redo, zoom, page width, find, word count, model, tools, attachments, chat and project navigation | PASS |
| Idle resource use | ~0.03 % CPU, ~16 MB working set |

## Not verified

- Windows 10.
- Multiple monitors, including unplugging one while the overlay is on it.
- A real Windows sign-out/sign-in. Startup was tested by launching the real Startup shortcut the
  way Explorer does.
- ChatGPT Classic in release 2.0.4 (it was tested in earlier builds).
- Chromium browsers other than Google Chrome (not supported).
- Loading the extension on a fresh PC through the installer's printed steps.

## Running the tests yourself

The suites press real hotkeys, so don't type while they run. Back up your `GhostOverlay.ini` first,
because the suite sets the opacity to 65 % during the run.

```
AutoHotkey64.exe Test-GhostOverlay.ahk Document     (or ChatGPT)
AutoHotkey64.exe Test-Startup.ahk Document          (or ChatGPT / Classic)
```
