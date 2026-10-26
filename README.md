# Ghost Overlay — a Windows workspace for ChatGPT

Summon ChatGPT as a small, semi-transparent, always-on-top overlay with one hotkey, and work in it
like a document. Dismiss it with the same hotkey and focus goes straight back to what you were doing.

[![Latest release](https://img.shields.io/github/v/release/dreisera007/ghost-overlay-windows?label=download)](https://github.com/dreisera007/ghost-overlay-windows/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
![AutoHotkey v2](https://img.shields.io/badge/AutoHotkey-v2-334455)

> **Independent project.** Ghost Overlay is not affiliated with, endorsed by, or sponsored by
> OpenAI, Google or Anthropic. ChatGPT is a trademark of OpenAI. Chrome is a trademark of Google LLC.
> Ghost Overlay does not modify ChatGPT or Chrome: it arranges their windows and styles your own
> chatgpt.com page locally.

![Document Workspace with a synthetic test conversation](docs/screenshots/workspace-desktop.png)

<p align="center">
  <img src="docs/screenshots/workspace-compact.png" alt="Compact overlay at 430 x 550" width="320">
  <img src="docs/screenshots/view-menu.png" alt="View menu with page-width settings" width="420">
</p>

## Download

**[Download the latest installer](https://github.com/dreisera007/ghost-overlay-windows/releases/latest)**
(`Install-ChatGPTGhostOverlay.cmd`, one file). Check its SHA256 against the value in the release notes.

> **The installer is not digitally signed.** It's a plain-text batch + PowerShell script, so you can
> open it in a text editor and read it before running it. Because it's an unsigned script downloaded
> from the internet, your browser may warn about the file type, and Windows SmartScreen may show an
> "unknown publisher" warning. Verify the SHA256 first. If you'd rather not run the installer, you
> can use the files from this repository directly (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Features

- **One hotkey.** `Ctrl+Alt+G` shows the overlay and focuses it; pressing it again hides it and gives
  focus back to the window you were using. Fast double-taps are queued, not dropped.
- **Adjustable transparency.** 5 % steps down to a 1 % floor, so it never goes fully invisible.
  Your setting is saved.
- **Always on top**, toggled with `Ctrl+Alt+T`. Position, size and opacity are remembered.
- **Emergency reset** (`Ctrl+Alt+Shift+R`): brings the window back fully opaque, on screen and focused,
  **without** overwriting your saved opacity.
- **Two windows, same hotkeys:**
  - **Document Workspace (default):** chatgpt.com in a dedicated Chrome app window, laid out as an
    original document editor. It has a header, menus (File, Edit, View, Insert, Format, Tools,
    Chats, Projects, Help), a toolbar, chat tabs, a ruler and a white page. Every menu item drives
    ChatGPT's own controls. Items whose control isn't available on the current page are greyed out.
  - **Native app (fallback):** the official ChatGPT Windows app, switched with one command.
- **Responsive page.** "Fit page to window", Narrow, Standard and Wide page widths. Small overlays
  (for example 430 × 550) fold the menus into one button. Works in ordinary and Project chats.
- **Starts at sign-in** if you want it to (per-user Startup shortcut, asked during install). It
  prepares the window hidden, so the first `Ctrl+Alt+G` is instant.
- **Safe by design.** It uses only standard Windows window calls (move, resize, opacity, topmost,
  show/hide) on one window. No API keys, no network calls of its own, no admin rights, no telemetry.

## Requirements

| | Tested with | Notes |
|---|---|---|
| Windows | Windows 11 (build 26200) | Windows 10 is untested |
| AutoHotkey | v2.0.23 | v2 required; the installer offers a free per-user install via `winget` |
| Google Chrome | 155 | For the Document Workspace. Other Chromium browsers are not supported |
| ChatGPT app | Microsoft Store app `OpenAI.Codex` 26.1021 | Only needed for the native fallback |
| PowerShell | 5.1 (built into Windows) | Used by the installer |

You need your own ChatGPT account (free or paid) and must be signed in to chatgpt.com in Chrome.
Ghost Overlay never asks for, reads or stores credentials.

## Install

1. Download `Install-ChatGPTGhostOverlay.cmd` from the
   [latest release](https://github.com/dreisera007/ghost-overlay-windows/releases/latest) and
   double-click it. The installer:
   - checks for the ChatGPT app, and offers the free Microsoft Store install only if you say yes
     (you can skip it if you only use the Document Workspace);
   - checks for AutoHotkey v2, and offers a free per-user install only if you say yes;
   - writes the files to `%LOCALAPPDATA%\ChatGPTGhostOverlay` (an existing configuration is kept);
   - picks the Document Workspace when Chrome is installed, otherwise the native app;
   - asks whether to start Ghost Overlay at Windows sign-in, then starts it.
2. **Load the extension once, by hand.** This step is required for the Document Workspace. Chrome
   doesn't let programs install extensions silently, and the extension isn't in the Chrome Web Store:
   1. Open `chrome://extensions` and turn on **Developer mode**.
   2. Click **Load unpacked** and choose `%LOCALAPPDATA%\ChatGPTGhostOverlay\DocumentMode\extension`.
   3. If you use several Chrome profiles, load it in the profile you use for ChatGPT, and put that
      profile's folder name in `GhostOverlay.ini` (for example `DocProfile=Profile 1`).
3. Press `Ctrl+Alt+G`.

The extension has **no permissions**. It acts only on chatgpt.com when the page runs as an app
window (`display-mode: standalone`), never in your normal tabs. It stores only view preferences and
sends nothing anywhere.

Installer options (from a terminal):

```
Install-ChatGPTGhostOverlay.cmd -Startup Yes|No|Ask       (default Ask)
Install-ChatGPTGhostOverlay.cmd -Mode Document|ChatGPT     (default: keep; new installs pick Document if Chrome exists)
Install-ChatGPTGhostOverlay.cmd -InstallDir C:\Tools\GhostOverlay
Install-ChatGPTGhostOverlay.cmd -Uninstall [-InstallDir ...]
```

Use an install folder without spaces. You can also run from a clone of this repository: see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Uninstall

```
Install-ChatGPTGhostOverlay.cmd -Uninstall
```

This stops the controller, hands the window back as a normal window, removes this copy's Startup
shortcut and deletes the installed files. Then remove **Ghost Overlay Document Mode** in
`chrome://extensions`. ChatGPT, Chrome and AutoHotkey stay installed.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| `Ctrl+Alt+G` | Show / hide the overlay. Opens the window if it isn't open yet (Document: about 2 s) |
| `Ctrl+Alt+Up` | More opaque (+5 %) |
| `Ctrl+Alt+Down` | More transparent (−5 %, down to 1 %; never fully invisible) |
| `Ctrl+Alt+T` | Toggle always-on-top |
| `Ctrl+Alt+Shift+R` | Emergency reset: temporarily 100 %, default size, bottom-right of the primary screen, focused. Saved opacity is kept |

Inside the Document Workspace, `Alt+Shift+M` opens the menus.

The tray icon (green **H**) offers Show/Hide, Reset, Mode, Open config, Reload and Exit.

## Switching windows

```
Switch-Mode.cmd ChatGPT     # native ChatGPT app overlay
Switch-Mode.cmd Document    # Document Workspace (default)
```

…or use tray → Mode. The setting is saved, and the previous window is handed back as a normal window.

## Configuration

`GhostOverlay.ini` sits next to `GhostOverlay.ahk` and is created on first run. See
[`GhostOverlay.example.ini`](GhostOverlay.example.ini) for every key. After editing, use tray →
**Reload config**.

| Key | Default | Meaning |
|---|---|---|
| `Target` | `ChatGPT`; the installer sets `Document` when Chrome is installed | `Document`, `ChatGPT` (Store app) or `Classic` (ChatGPT Classic) |
| `Width` / `Height` | `430` / `550` | Overlay size in DPI-independent pixels |
| `Opacity` | `30` | Percent; saved by the opacity hotkeys |
| `OpacityStep` / `MinOpacity` | `5` / `1` | Step per keypress and the floor |
| `AlwaysOnTop` | `1` | Saved by `Ctrl+Alt+T` |
| `DocProfile` | blank | Chrome profile folder; blank = Chrome's last-used profile |
| `DocBrowser` / `DocUrl` | blank / `https://chatgpt.com/` | Path to `chrome.exe` (blank = found automatically) and the start page |

## Privacy and security

- Ghost Overlay never reads, copies or uploads your conversations, cookies, tokens or passwords.
- It never calls the OpenAI API, proxies traffic or injects code into the ChatGPT desktop app.
- The controller finds its window by the exact Windows app identity Chrome gives the chatgpt.com app
  window. Ordinary Chrome windows and other profiles are never touched.
- `GhostOverlay.log` (next to the controller) records only window handles, window sizes, modes and
  saved-opacity changes, never page content.
- **Transparency is not privacy.** Screen sharing, recordings and people near you can still see a
  translucent window. Hide it with `Ctrl+Alt+G`.

Found a vulnerability? Please follow [SECURITY.md](SECURITY.md).

## Known limitations

- **Depends on ChatGPT's page structure.** The workspace hooks ChatGPT's own `data-*` attributes. A
  ChatGPT update can break some styling or menu items until Ghost Overlay is updated. Meanwhile,
  use File → Original ChatGPT layout or `Switch-Mode.cmd ChatGPT`.
- **Chrome only** for the Document Workspace (Google Chrome at its standard install path, or
  `DocBrowser=`).
- **The extension is loaded unpacked**, so Chrome shows its usual developer-mode notice.
- **Chrome's thin title bar** follows your Chrome profile theme; a page can't recolour it.
- **Native app minimum size** is about 547 × 684, so 430 × 550 is clamped in native mode.
- **Untested:** Windows 10, multiple monitors, a real sign-out/sign-in (startup was tested by
  launching the real Startup shortcut), and ChatGPT Classic in this release.

## How it works

The controller (`GhostOverlay.ahk`, AutoHotkey v2) registers the five hotkeys. It applies opacity
and topmost to one window and runs a 1.5 s watchdog that re-applies them if anything resets them
(~0.01–0.05 % CPU, ~17 MB RAM). The Document Workspace is a Manifest V3 content script and
stylesheet in [`DocumentMode/extension`](DocumentMode/extension). [docs/TESTING.md](docs/TESTING.md)
lists what has been verified and how.

## Contributing

Bug reports, ideas and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md)
first, and never paste real conversation content into issues or screenshots.

## Acknowledgements

Ghost Overlay was developed with AI assistance (Anthropic's Claude). The maintainer directed,
reviewed and tested the work; the test results are in [docs/TESTING.md](docs/TESTING.md).

## License

[MIT](LICENSE). Copyright (c) 2026 dreisera007.
