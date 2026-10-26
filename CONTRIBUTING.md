# Contributing to Ghost Overlay

Thanks for helping. Bug reports, small fixes, ChatGPT layout updates and documentation are all welcome.

## Ground rules

- **Privacy first.** Never paste real conversation text, chat or project titles, account names,
  cookies, tokens or logs you haven't read into issues, pull requests or screenshots. Use a new chat
  with made-up content (or a Temporary chat) when you need to show something.
- **No credentials, no APIs, no traffic interception.** Ghost Overlay arranges windows and styles the
  user's own chatgpt.com page locally. The extension may read the page only to display it in the
  workspace (see README → Privacy and security), and every new read must be documented there.
  Contributions that send page content anywhere, store conversations, call the OpenAI API, proxy or
  modify network traffic, or inject code into the ChatGPT desktop app won't be accepted.
- **No look-alike branding.** The Document Workspace uses an original design. Don't add logos,
  icons or assets from other products (for example Google Docs).
- **Keep the extension's footprint minimal.** `DocumentMode/extension/manifest.json` declares no
  Chrome API permissions and no background worker, and matches only `https://chatgpt.com/*`. Please
  keep it that way.

## Project layout

| Path | What it is |
|---|---|
| `GhostOverlay.ahk` | The controller (AutoHotkey v2): hotkeys, window discovery, opacity/topmost, watchdog |
| `DocumentMode/extension/` | Manifest V3 content script (`docmode.js`) and stylesheet (`docmode.css`) |
| `Start-GhostOverlay.cmd`, `Stop-GhostOverlay.cmd`, `Switch-Mode.cmd` | Launchers |
| `Install-Startup.ps1`, `Uninstall.ps1` | Per-user Startup shortcut and uninstaller |
| `Build-Installer.ps1` | Packs the files into the single-file installer |
| `Test-GhostOverlay.ahk`, `Test-Startup.ahk` | Black-box functional tests that drive the real hotkeys |
| `GhostOverlay.example.ini` | Every configuration key with its default |

## Running from a clone

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Load `DocumentMode/extension` unpacked in Chrome (`chrome://extensions` → Developer mode →
   Load unpacked).
3. Optional: copy `GhostOverlay.example.ini` to `GhostOverlay.ini` and edit it. Without one, the
   controller writes its own default on first start (`Target=ChatGPT`; set `Target=Document` for the
   workspace).
4. Run `Start-GhostOverlay.cmd`; stop with `Stop-GhostOverlay.cmd`.

Only one controller runs at a time. Stop an installed copy before starting one from your clone.

## Checks before a pull request

- **Syntax:** `AutoHotkey64.exe /ErrorStdOut /validate GhostOverlay.ahk` must exit with code 0 (also
  run it for the test scripts if you changed them).
- **Functional tests** (they press the real hotkeys, so don't type while they run):
  `AutoHotkey64.exe Test-GhostOverlay.ahk Document` or `... ChatGPT`. The suite sets the opacity to
  65 % during the run, so back up your `GhostOverlay.ini` first.
- **Extension changes:** reload the extension in `chrome://extensions`, then check an ordinary chat,
  a chat inside a Project, the start page, and the compact size (about 430 × 550). The workspace
  must not appear in ordinary Chrome tabs.
- **Installer changes:** run `powershell -ExecutionPolicy Bypass -File .\Build-Installer.ps1`, then
  test with `-InstallDir` pointing to a throw-away folder. Don't commit the generated
  `Install-ChatGPTGhostOverlay.cmd`; it is attached to releases.
- Update `CHANGELOG.md` under **Unreleased**.

## Code style

- AutoHotkey v2 only. Match the surrounding code: short functions, comments that explain *why*.
- In `docmode.js`, find ChatGPT elements through stable `data-*` attributes or `aria-label`s, and
  use the `shown()` helper: ChatGPT keeps hidden copies of recently visited pages, so the first
  match is often invisible.
- Keep page widths in pixels: ChatGPT reuses the width variable in its own centring maths.

## Reporting bugs

Use the bug report form. Include your Windows, Chrome, AutoHotkey and Ghost Overlay versions, the
mode (`Document` or `ChatGPT`), and the steps that cause the problem. If you attach
`GhostOverlay.log`, read it first; it contains only window handles, sizes and settings.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
