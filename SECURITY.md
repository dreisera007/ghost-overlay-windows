# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 2.0.x (latest release) | Yes |
| Older builds | No; please update to the latest release |

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub: **Security → Report a vulnerability** on this repository (private
vulnerability reporting). Include:

- what an attacker could do, and under which conditions;
- steps to reproduce on a test setup;
- the affected version and mode (`Document` or `ChatGPT`).

Never include real conversation content, cookies, tokens or passwords in a report. You should get a
first response within 7 days. Fixes are released as a new version, with credit to the reporter
unless they'd rather stay anonymous.

## Security model

What Ghost Overlay does:

- The controller calls standard Windows window functions (show/hide, move, resize, opacity,
  topmost) on **one** window. It identifies that window by its exact Windows app identity, process
  path and window class.
- The Chrome extension declares **no Chrome API permissions** and has no background worker. Its
  content script is matched to `https://chatgpt.com/*` and switches the workspace on only in the
  standalone app window. It reads that page locally to display it: ChatGPT's chat and project
  navigation, the conversation title and model name, and, only when you use Find, Word count, Print
  or Download as text, the displayed conversation. It reads the clipboard only on Edit → Paste. It
  stores only view preferences in chatgpt.com's `localStorage` (shared by that origin in the Chrome
  profile). It makes no network requests of its own; ChatGPT's own traffic to OpenAI continues as
  normal.
- The installer writes files to a per-user folder. It installs third-party software (AutoHotkey,
  the ChatGPT Store app) only through `winget` / the Microsoft Store, and only after you agree.

What it never does:

- store or transmit conversations, or read credentials, cookies or tokens;
- call the OpenAI API, run a separate AI backend, or contact any other network service of its own;
- proxy or intercept traffic, or inject code into the ChatGPT desktop app;
- add Run registry keys, scheduled tasks or services (startup uses one per-user Startup shortcut).

In scope: privilege escalation, code execution via the installer or configuration, the controller
acting on the wrong window, and the extension exposing page data. Out of scope: weaknesses in
ChatGPT, Chrome, Windows or AutoHotkey themselves (report those to their vendors), and the fact
that a translucent window is visible to people near your screen.
