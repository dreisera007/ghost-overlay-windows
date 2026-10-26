# Packs the current, tested project files into one self-contained installer:
#   Install-ChatGPTGhostOverlay.cmd  (double-click to run; it is batch + PowerShell in one file)
# Re-run this after changing any project file so the installer stays in sync.
param([string]$OutFile = (Join-Path $PSScriptRoot 'Install-ChatGPTGhostOverlay.cmd'))   # where the installer is written
$ErrorActionPreference = 'Stop'
$files = 'GhostOverlay.ahk', 'Start-GhostOverlay.cmd', 'Stop-GhostOverlay.cmd', 'Switch-Mode.cmd', 'Install-Startup.ps1',
         'Uninstall.ps1', 'Test-GhostOverlay.ahk', 'Test-Startup.ahk', 'README.md', 'LICENSE',
         'DocumentMode\extension\manifest.json', 'DocumentMode\extension\docmode.js', 'DocumentMode\extension\docmode.css'
$payload = foreach ($f in $files) {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $f)))
    "    '$f' = '$b64'"
}

$header = @'
<# :
@echo off
rem ===== ChatGPT Ghost Overlay - single-file installer =====
rem Double-click to install. Options (from a terminal):
rem   Install-ChatGPTGhostOverlay.cmd -Startup Yes|No|Ask -Mode Document|ChatGPT -InstallDir <folder> -RunTests
rem   Install-ChatGPTGhostOverlay.cmd -Uninstall [-InstallDir <folder>]
rem The PowerShell below runs with ExecutionPolicy Bypass for this process only.
setlocal
set "GO_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:GO_SELF))) %*"
set "rc=%errorlevel%"
echo %cmdcmdline% | find /i "%~nx0" >nul && pause
exit /b %rc%
#>
'@

$body = @'
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'ChatGPTGhostOverlay'),
    [ValidateSet('Ask', 'Yes', 'No')][string]$Startup = 'Ask',
    [ValidateSet('Keep', 'Document', 'ChatGPT')][string]$Mode = 'Keep',
    [switch]$Uninstall,
    [switch]$RunTests
)
# What this installer does (and never does):
#  - checks for the official ChatGPT app (Microsoft Store, publisher OpenAI) and AutoHotkey v2,
#    offering free installs via winget only after you say yes; per-user first, admin only if you agree
#  - writes the overlay files to $InstallDir, keeps an existing GhostOverlay.ini (your settings)
#  - Document Mode (default for new installs when Chrome is present): chatgpt.com in a Chrome app
#    window, styled by a local extension you load yourself (Chrome does not allow silent installs)
#  - optionally adds a per-user Startup shortcut (asks first)
#  - never modifies ChatGPT, never reads credentials, no API keys, no paid services,
#    never restarts or signs out of Windows, touches no other startup items
$ErrorActionPreference = 'Stop'
$StoreId = '9PLM9XGG6VKS'   # "ChatGPT" by OpenAI in the Microsoft Store

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Ask([string]$q, [bool]$def = $true) {
    $a = Read-Host ("$q " + $(if ($def) { '[Y/n]' } else { '[y/N]' }))
    if ([string]::IsNullOrWhiteSpace($a)) { return $def }
    return $a.Trim() -match '^(y|yes)$'
}
function Find-Chrome {
    @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
      "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
}
function Set-IniValue([string]$path, [string]$key, [string]$value) {   # keeps the file's encoding
    $sr = New-Object IO.StreamReader($path, $true); $txt = $sr.ReadToEnd(); $enc = $sr.CurrentEncoding; $sr.Close()
    [IO.File]::WriteAllText($path, ($txt -replace "(?m)^$key=.*?(\r?)$", "$key=$value`$1"), $enc)
}
function Find-Ahk {
    @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
# Number of controllers running from THIS folder. Always an [int]: on Windows PowerShell 5.1 a
# single CimInstance has no .Count, so the result must be wrapped in @() by the caller's side.
function Get-ControllerCount {
    $me = (Join-Path $InstallDir 'GhostOverlay.ahk')
    [int]@(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains('"' + $me + '"') }).Count
}
# Command lines of controllers running from OTHER folders (only one controller may run at a time).
function Get-OtherControllers {
    $me = '"' + (Join-Path $InstallDir 'GhostOverlay.ahk') + '"'
    @(Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'" |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*GhostOverlay.ahk*' -and -not $_.CommandLine.Contains($me) } |
        ForEach-Object { $_.CommandLine })
}
# True only if the Startup shortcut launches THIS folder's controller.
function Test-OwnStartup {
    if (-not (Test-Path $StartupLnk)) { return $false }
    $a = (New-Object -ComObject WScript.Shell).CreateShortcut($StartupLnk).Arguments
    return $a.Contains('"' + (Join-Path $InstallDir 'GhostOverlay.ahk') + '"')
}
function Stop-Controller {
    $ahk = Find-Ahk; $s = Join-Path $InstallDir 'GhostOverlay.ahk'
    if ($ahk -and (Test-Path $s) -and (Get-ControllerCount) -gt 0) {
        Start-Process $ahk -ArgumentList ('"' + $s + '"'), '--stop' -Wait
    }
}
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'ChatGPT Ghost Overlay.lnk'

if ($Uninstall) {
    if (-not (Test-Path (Join-Path $InstallDir 'Uninstall.ps1'))) { Say "Nothing installed at $InstallDir" Yellow; return }
    & (Join-Path $InstallDir 'Uninstall.ps1') -RemoveFiles
    if (-not (Get-ChildItem $InstallDir -Force)) { Remove-Item $InstallDir }
    Say 'Uninstalled. ChatGPT and AutoHotkey were left installed.' Green
    return
}

Say '== ChatGPT Ghost Overlay installer ==' Cyan
Say "Install folder: $InstallDir"

# ---- 1. ChatGPT (official Store app)
$codex = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue
$classic = Get-AppxPackage -Name 'OpenAI.ChatGPT-Desktop' -ErrorAction SilentlyContinue
if (-not $codex -and -not $classic) {
    Say 'The ChatGPT app (Microsoft Store, publisher OpenAI) is not installed.' Yellow
    if (Ask 'Install it now from the Microsoft Store (free)?') {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id $StoreId --source msstore --accept-package-agreements --accept-source-agreements
        } else {
            Start-Process "ms-windows-store://pdp/?ProductId=$StoreId"
            Read-Host 'Install ChatGPT in the Store window, then press Enter here' | Out-Null
        }
        $codex = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue
    }
    if (-not $codex) { Say 'ChatGPT not found yet. The overlay will work as soon as it is installed.' Yellow }
}
foreach ($p in @($codex, $classic) | Where-Object { $_ }) {
    Say ("Found {0} {1} (signature: {2})" -f $p.Name, $p.Version, $p.SignatureKind)
}
if ($codex -or $classic) { Say 'Sign in to ChatGPT yourself in the app; this installer never handles credentials.' }

# ---- 2. AutoHotkey v2
$ahk = Find-Ahk
if (-not $ahk) {
    Say 'AutoHotkey v2 (free, open source) is required and not installed.' Yellow
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available. Install AutoHotkey v2 from https://www.autohotkey.com/ and run this installer again.'
    }
    if (Ask 'Install AutoHotkey v2 for this user only (no admin needed)?') {
        winget install --id AutoHotkey.AutoHotkey -e --scope user --silent --accept-package-agreements --accept-source-agreements
        $ahk = Find-Ahk
        if (-not $ahk -and (Ask 'Per-user install did not work. Install for all users? (Windows will ask for admin approval)' $false)) {
            winget install --id AutoHotkey.AutoHotkey -e --scope machine --accept-package-agreements --accept-source-agreements
            $ahk = Find-Ahk
        }
    }
    if (-not $ahk) { throw 'AutoHotkey v2 is required. Nothing was installed.' }
}
$ahkVer = (Get-Item $ahk).VersionInfo.ProductVersion
if ($ahkVer -notlike '2.*') { throw "AutoHotkey $ahkVer found, but v2 is required." }
Say "AutoHotkey: $ahk ($ahkVer)"

# ---- 3. Files (an existing GhostOverlay.ini is kept)
Stop-Controller
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
foreach ($k in $Payload.Keys) {
    $dest = Join-Path $InstallDir $k
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    [IO.File]::WriteAllBytes($dest, [Convert]::FromBase64String($Payload[$k]))
}
Say "Wrote $($Payload.Count) files to $InstallDir"
$ini = Join-Path $InstallDir 'GhostOverlay.ini'
if (-not (Test-Path $ini)) {
    # the controller writes its own commented default config (and exits; nothing else is started)
    Start-Process $ahk -ArgumentList ('"' + (Join-Path $InstallDir 'GhostOverlay.ahk') + '"'), '--init-config' -Wait
    if (-not (Test-Path $ini)) { throw 'Could not create the default GhostOverlay.ini.' }
    if ($Mode -eq 'Keep') { $Mode = if (Find-Chrome) { 'Document' } elseif ($codex) { 'ChatGPT' } else { 'Keep' } }
    if (-not $codex -and $classic -and $Mode -eq 'Keep') {
        Set-IniValue $ini 'Target' 'Classic'
        Say 'Only ChatGPT Classic found: config set to Target=Classic.'
    }
    Say 'Created default config (430x550, 30% opacity, 1% minimum, always on top).'
} else {
    Say 'Kept your existing GhostOverlay.ini settings.'
    # Older versions shipped MinOpacity=20 as the default floor; lower only that untouched default
    # to the new 1 % floor. Opacity and any custom MinOpacity are left as they are.
    $sr = New-Object IO.StreamReader($ini, $true); $txt = $sr.ReadToEnd(); $enc = $sr.CurrentEncoding; $sr.Close()
    if ($txt -match '(?m)^MinOpacity=20\r?$') {
        [IO.File]::WriteAllText($ini, ($txt -replace '(?m)^MinOpacity=20(\r?)$', 'MinOpacity=1$1'), $enc)
        Say 'Opacity floor lowered from 20% to 1% (your saved opacity is unchanged).'
    }
}
if ($Mode -ne 'Keep') {
    Set-IniValue $ini 'Target' $Mode
    Say "Overlay mode: $Mode $(if ($Mode -eq 'Document') { '(Chrome app window, document workspace)' } else { '(native ChatGPT app)' })"
}

# ---- 3b. Document Mode: the browser extension is loaded by you, once (Chrome forbids silent installs)
$extDir = Join-Path $InstallDir 'DocumentMode\extension'
if ((Select-String -Path $ini -Pattern '^Target=Document' -Quiet)) {
    Say ''
    Say 'Document Mode needs its local Chrome extension (one time, about 30 seconds):' Cyan
    Say '  1. In Chrome, open chrome://extensions and turn on "Developer mode" (top right).'
    Say '  2. Click "Load unpacked" and choose this folder:'
    Say "       $extDir" White
    Say '  3. Sign in to chatgpt.com in that Chrome profile if you are not already.'
    Say '  If you use several Chrome profiles, put the profile folder name (e.g. Profile 1) in'
    Say '  GhostOverlay.ini as DocProfile=... so the overlay opens in the right one.'
    Say '  The extension declares no Chrome API permissions. It runs only on chatgpt.com, styles only the'
    Say '  overlay''s app window, and renames a chat only through ChatGPT''s own Rename dialog.'
    $chrome = Find-Chrome
    if ($chrome -and (Ask 'Open chrome://extensions now?' $false)) { Start-Process $chrome 'chrome://extensions' }
    Say 'To switch back to the native ChatGPT app at any time: Switch-Mode.cmd ChatGPT'
}

# ---- 4. Optional tests (they drive the hotkeys; don't type while they run)
if ($RunTests) {
    $target = (Select-String -Path $ini -Pattern '^Target=(\w+)').Matches[0].Groups[1].Value
    Say "Running functional tests against $target (~2.5 min). Please don't touch the keyboard or mouse..." Yellow
    $bak = "$ini.bak"; Copy-Item $ini $bak -Force
    $out = Join-Path $env:TEMP 'GhostOverlay-tests.txt'
    $t = Start-Process $ahk -ArgumentList '/ErrorStdOut', ('"' + (Join-Path $InstallDir 'Test-GhostOverlay.ahk') + '"'), $target -RedirectStandardOutput $out -PassThru -Wait
    Get-Content $out | ForEach-Object { if ($_ -like 'FAIL*') { Say $_ Red } elseif ($_ -like 'PASS*') { Say $_ DarkGreen } else { Say $_ } }
    Copy-Item $bak $ini -Force; Remove-Item $bak
    $c = [IO.File]::ReadAllText($ini); $i2 = $c.IndexOf('[State]')
    if ($i2 -ge 0) { [IO.File]::WriteAllText($ini, $c.Substring(0, $i2 + 7) + "`r`n") }
}

# ---- 5. Start at login (asks)
$enable = switch ($Startup) {
    'Yes' { $true } 'No' { $false }
    default { Ask 'Start the overlay controller automatically when you sign in to Windows?' }
}
if ($enable) {
    & (Join-Path $InstallDir 'Install-Startup.ps1')
} else {
    & (Join-Path $InstallDir 'Install-Startup.ps1') -Remove | Out-Null   # only removes our own shortcut
    Say 'Automatic startup: not enabled (run Install-Startup.ps1 later to enable).'
}

# ---- 6. Start the controller now (exactly as at login if startup is enabled)
$others = Get-OtherControllers
$n = 0
if ($others.Count) {
    Say 'Not started: another Ghost Overlay copy is already running (only one can run at a time):' Yellow
    $others | ForEach-Object { Say "  $_" Yellow }
    Say '  Stop it with its Stop-GhostOverlay.cmd, then run Start-GhostOverlay.cmd in this folder.' Yellow
} else {
    if ($enable) { Start-Process $StartupLnk } else { Start-Process $ahk -ArgumentList ('"' + (Join-Path $InstallDir 'GhostOverlay.ahk') + '"') }
    for ($i = 0; $i -lt 40; $i++) {   # wait up to 10 s for the controller to come up
        Start-Sleep -Milliseconds 250
        $n = Get-ControllerCount
        if ($n -ge 1) { Start-Sleep -Milliseconds 3500; $n = Get-ControllerCount; break }   # a refused copy exits within ~3 s
    }
}
if ($others.Count) { }
elseif ($n -eq 1) { Say 'Controller running (1 instance).' Green }
elseif ($n -eq 0) { Say 'Controller is not running from this folder. Another copy may already be running (only one is allowed); stop it with its Stop-GhostOverlay.cmd, then run Start-GhostOverlay.cmd here.' Yellow }
else { Say "Warning: $n controllers running from this folder." Red }

Say ''
Say 'Done. Hotkeys:' Cyan
Say '  Ctrl+Alt+G          show / hide ChatGPT overlay'
Say '  Ctrl+Alt+Up / Down  more opaque / more transparent'
Say '  Ctrl+Alt+T          toggle always-on-top'
Say '  Ctrl+Alt+Shift+R    emergency reset (fully visible, default size)'
Say '  Switch-Mode.cmd Document | ChatGPT   change the overlay window (Document workspace / native app)'
if (Test-OwnStartup) { Say 'Startup at login: ENABLED (for this install)' }
elseif (Test-Path $StartupLnk) { Say 'Startup at login: disabled for this install (the existing Startup shortcut belongs to another copy and was left unchanged)' }
else { Say 'Startup at login: disabled' }
Say "Files: $InstallDir   (README.md explains everything; Uninstall: run this installer with -Uninstall)"
'@

$out = $OutFile
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
# inject the embedded files right after the first "$ErrorActionPreference = 'Stop'" line of the body
$anchor = "`$ErrorActionPreference = 'Stop'"
$at = $body.IndexOf($anchor) + $anchor.Length
$text = $header + "`r`n" + $body.Substring(0, $at) + "`r`n`$Payload = @{`r`n" + ($payload -join "`r`n") + "`r`n}" + $body.Substring($at)
[IO.File]::WriteAllText($out, ($text -replace "(?<!`r)`n", "`r`n"), (New-Object Text.UTF8Encoding $false))
"Built $out ($([math]::Round((Get-Item $out).Length / 1KB)) KB, $($files.Count) files embedded)"
