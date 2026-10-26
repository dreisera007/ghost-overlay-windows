# Adds (or with -Remove, deletes) a per-user Startup shortcut for the overlay controller.
# Per-user only: no admin rights, no registry Run keys, no scheduled tasks.
# The shortcut starts only the controller (AutoHotkey + GhostOverlay.ahk --startup); it never
# launches ChatGPT. --startup makes a duplicate launch exit silently.
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$name = 'ChatGPT Ghost Overlay.lnk'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) $name
# Task Manager's enable/disable flag for Startup-folder items (only our own entry is touched)
$approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
if ($Remove) {
    if (-not (Test-Path $lnk)) { "No startup shortcut present."; return }
    $args0 = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).Arguments
    if ($args0 -notlike ('*"' + (Join-Path $PSScriptRoot 'GhostOverlay.ahk') + '"*')) {
        "Startup shortcut belongs to another copy ($args0); left unchanged."
        return
    }
    Remove-Item $lnk
    Remove-ItemProperty -Path $approved -Name $name -ErrorAction SilentlyContinue
    "Removed startup shortcut: $lnk"
    return
}
$ahk = @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $ahk) { throw 'AutoHotkey v2 not found.' }
$script = Join-Path $PSScriptRoot 'GhostOverlay.ahk'
if (-not (Test-Path $script)) { throw "Controller not found: $script" }
$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk)
$s.TargetPath = $ahk
$s.Arguments = '"' + $script + '" --startup'
$s.WorkingDirectory = $PSScriptRoot
$s.Description = 'ChatGPT Ghost Overlay controller'
$s.Save()
Remove-ItemProperty -Path $approved -Name $name -ErrorAction SilentlyContinue   # clear a stale "disabled" flag
"Created startup shortcut: $lnk"
"  Target:    $ahk"
"  Arguments: " + $s.Arguments
