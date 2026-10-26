; Login-simulation tests: launches the real Startup shortcut (as Explorer does at login) and checks
; that only the controller starts, the ChatGPT window is prepared hidden with no visible flash,
; Ctrl+Alt+G is instant, and repeated launches never create a second controller.
; Usage: AutoHotkey64.exe Test-Startup.ahk [ChatGPT|Classic]
;   Classic = full "app is in the tray" scenario (closes and restarts ChatGPT Classic).
;   ChatGPT = "app window already open at login" scenario (never closes ChatGPT).
#Requires AutoHotkey v2.0
#SingleInstance Force
SetWinDelay 0
SendLevel 1
DetectHiddenWindows true
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

targetName := A_Args.Length ? A_Args[1] : "ChatGPT"
pathPart := targetName = "Classic" ? "\OpenAI.ChatGPT-Desktop_" : targetName = "Document" ? "\chrome.exe" : "\OpenAI.Codex_"
aumid := targetName = "Classic" ? "OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT" : "OpenAI.Codex_2p2nqsd0c76g0!App"
dir := A_ScriptDir
ini := dir "\GhostOverlay.ini"
lnk := A_Startup "\ChatGPT Ghost Overlay.lnk"
pass := 0, fail := 0, out := ""

Check(name, cond, detail := "") {
    global pass, fail, out
    (cond ? pass++ : fail++)
    out .= (cond ? "PASS  " : "FAIL  ") name (detail != "" ? "  [" detail "]" : "") "`n"
}
Target() {
    ; the controller always keeps to the window it used last, so check that one first
    try if targetName = "Document" && (p := Integer(IniRead(ini, "State", "AppliedTo", 0))) && WinExist(p) && AppId(p) = DocId()
        return p
    for h in WinGetList("ahk_class Chrome_WidgetWin_1")
        try if InStr(WinGetProcessPath(h), pathPart) && (WinGetStyle(h) & 0xC40000) = 0xC40000
            && !(WinGetExStyle(h) & 0x20) && WinGetTitle(h) != ""
            && (targetName != "Document" || AppId(h) = DocId())
            return h
    return 0
}
; App ID of the Document window for the default DocUrl (https://chatgpt.com/) in DocProfile.
DocId() => "Chrome.chatgpt.com_/" (IniRead(ini, "Overlay", "DocProfile", "") ~= "^(Default)?$" ? "" : ".UserData." RegExReplace(IniRead(ini, "Overlay", "DocProfile"), "[^A-Za-z0-9.]"))
; Windows app ID of a window (Document Mode's Chrome app window is "Chrome.chatgpt.com_/...").
AppId(h) {
    iid := Buffer(16), key := Buffer(20), pv := Buffer(24, 0), ps := 0, s := ""
    DllCall("ole32\CLSIDFromString", "str", "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}", "ptr", iid)
    if DllCall("shell32\SHGetPropertyStoreForWindow", "ptr", h, "ptr", iid, "ptr*", &ps) != 0 || !ps
        return ""
    DllCall("ole32\CLSIDFromString", "str", "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}", "ptr", key)
    NumPut("uint", 5, key, 16)
    try {
        ComCall(5, ps, "ptr", key, "ptr", pv)
        if NumGet(pv, 0, "ushort") = 31
            s := StrGet(NumGet(pv, 8, "ptr"))
    }
    DllCall("ole32\PropVariantClear", "ptr", pv), ObjRelease(ps)
    return s
}
Vis(h) => h && DllCall("IsWindowVisible", "ptr", h)
Alpha(h) => h && WinExist(h) ? WinGetTransparent(h) : "n/a"
Controllers() {
    n := 0
    for p in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where Name like 'AutoHotkey%'")
        try if InStr(p.CommandLine, dir "\GhostOverlay.ahk")
            n++
    return n
}
LogHas(text) {
    try return InStr(FileRead(dir "\GhostOverlay.log"), text)
    return 0
}

Check("startup shortcut exists", FileExist(lnk))
FileGetShortcut lnk, &lt, &ld, &la
Check("shortcut target is AutoHotkey v2", InStr(lt, "AutoHotkey64.exe") && FileExist(lt), lt)
Check("shortcut runs this project's controller with --startup", la = '"' dir '\GhostOverlay.ahk" --startup', la)
Check("shortcut working dir is the project", ld = dir, ld)

; ---- reset to a logged-out-like state
RunWait '"' dir '\Stop-GhostOverlay.cmd"', , "Hide"
IniWrite targetName, ini, "Overlay", "Target"
try IniDelete ini, "State"
if targetName = "Classic" {
    for p in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, ExecutablePath from Win32_Process")
        try if InStr(p.ExecutablePath, pathPart)
            ProcessClose p.ProcessId
    Sleep 1500
    Run 'explorer.exe "shell:AppsFolder\' aumid '"'   ; stands in for the app's own login start (to tray)
    loop 80 {
        Sleep 250
        if Target() && !Vis(Target())
            break
    }
    h := Target()
    if Vis(h) {   ; this cold start showed the window: put it in the tray the app's way
        WinClose h
        Sleep 1500
    }
    h := Target()
    Check("precondition: app running with window hidden in tray", h && !Vis(h))
} else {
    h := Target()
    Check("precondition: ChatGPT window present", h)
}
wasVisible := Vis(h)
FileAppend "", dir "\GhostOverlay.log"
logStart := FileGetSize(dir "\GhostOverlay.log")

; ---- simulated login: Explorer launches the shortcut; sample the window for any visible flash
Run lnk
flash := 0, samples := 0, t0 := A_TickCount, ready := false
while A_TickCount - t0 < 40000 {
    if Vis(h) && Alpha(h) != 0 && !wasVisible
        flash++
    samples++
    if !ready && Mod(samples, 20) = 0   ; read the log only every ~200 ms so the controller can write it
        && InStr(SubStr(FileRead(dir "\GhostOverlay.log"), logStart + 1), "prewarmed")
        ready := A_TickCount - t0
    if ready && A_TickCount - t0 > ready + 500
        break
    Sleep 10
}
Check("controller started from shortcut", Controllers() = 1)
Check("window prepared in advance (prewarmed)", ready, ready ? ready " ms after launch" : "not within 40 s")
Check("no visible flash while preparing", flash = 0, flash " of " samples " samples visible")
Check("ChatGPT window hidden by default", !Vis(h))
Check("opacity pre-set for first show", Alpha(h) = Round(IniRead(ini, "Overlay", "Opacity") * 2.55), "alpha=" Alpha(h))

; ---- duplicates: login + manual double launches
Run lnk
Run lnk
Sleep 3500
Check("repeated shortcut launches don't duplicate", Controllers() = 1, Controllers() " running")
Check("no 'already running' popup for startup launches", !WinExist("Ghost Overlay ahk_class #32770"))

; ---- first Ctrl+Alt+G is instant
g := Gui("+ToolWindow", "StartupProbe"), g.Show("x60 y60 w200 h60"), WinActivate(g.Hwnd)
Sleep 400
t1 := A_TickCount
SendInput "^!g"
while !(Vis(h) && WinActive(h)) && A_TickCount - t1 < 5000
    Sleep 5
lat := A_TickCount - t1
Check("first Ctrl+Alt+G shows + focuses ChatGPT", Vis(h) && WinActive(h))
Check("first Ctrl+Alt+G latency < 300 ms", lat < 300, lat " ms")
Sleep 300
SendInput "^!g"
Sleep 700
Check("Ctrl+Alt+G hides it again, focus returned", !Vis(h) && WinActive(g.Hwnd))
g.Destroy()

FileAppend Format("`nStartup ({}): {} passed, {} failed`n", targetName, pass, fail) out, "*"
ExitApp fail ? 1 : 0
