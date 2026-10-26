# Uninstalls ChatGPT Ghost Overlay.
#  - stops the controller (ChatGPT window is restored to a normal window)
#  - removes the per-user Startup shortcut if present
#  - with -RemoveFiles, deletes this overlay's own files from this folder
# It never touches the ChatGPT app, AutoHotkey, or any other program.
param([switch]$RemoveFiles)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$ahk = @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe") |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($ahk) {
    Start-Process -FilePath $ahk -ArgumentList ('"' + (Join-Path $here 'GhostOverlay.ahk') + '"'), '--stop' -Wait
    'Controller stopped.'
}
& (Join-Path $here 'Install-Startup.ps1') -Remove
if ($RemoveFiles) {
    $ours = 'GhostOverlay.ahk','GhostOverlay.ini','GhostOverlay.log','Start-GhostOverlay.cmd','Stop-GhostOverlay.cmd',
            'Install-Startup.ps1','README.md','Test-GhostOverlay.ahk','Test-Startup.ahk','TEST-RESULTS.md','Uninstall.ps1','Switch-Mode.cmd','LICENSE'
    foreach ($f in $ours) { $p = Join-Path $here $f; if (Test-Path $p) { Remove-Item $p -Force } }
    $ext = Join-Path $here 'DocumentMode'; if (Test-Path $ext) { Remove-Item $ext -Recurse -Force }   # remove it from chrome://extensions too
    "Removed overlay files from $here"
} else {
    "Files kept in $here (run with -RemoveFiles to delete them)."
}
