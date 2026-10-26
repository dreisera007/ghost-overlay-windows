; Black-box functional tests for GhostOverlay.ahk. Drives the real hotkeys and inspects the
; real ChatGPT window. Usage: AutoHotkey64.exe Test-GhostOverlay.ahk [ChatGPT|Classic] [restart]
;   restart = also kill + relaunch the target app to test recovery (use only with Classic or
;             when you don't mind ChatGPT restarting).
; WARNING: synthetic keystrokes go to whatever has focus. Don't type during the ~2.5 min run,
; and check ChatGPT's message box afterwards for stray characters if any test failed.
#Requires AutoHotkey v2.0
#SingleInstance Force
SetWinDelay 0
SendLevel 1   ; let hook-based hotkeys (Ctrl+Alt+Up/Down) see our synthetic keys like physical ones
DetectHiddenWindows true
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

targetName := A_Args.Length ? A_Args[1] : "ChatGPT"
doRestart := A_Args.Length > 1 && A_Args[2] = "restart"
pathPart := targetName = "Classic" ? "\OpenAI.ChatGPT-Desktop_" : targetName = "Document" ? "\chrome.exe" : "\OpenAI.Codex_"
aumid := targetName = "Classic" ? "OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT" : "OpenAI.Codex_2p2nqsd0c76g0!App"
dir := A_ScriptDir
ini := dir "\GhostOverlay.ini"
pass := 0, fail := 0, out := ""

Check(name, cond, detail := "") {
    global pass, fail, out
    (cond ? pass++ : fail++)
    out .= (cond ? "PASS  " : "FAIL  ") name (detail != "" ? "  [" detail "]" : "") "`n"
}
Hk(keys, wait := 700) {
    SendInput keys
    Sleep wait
}
Target() {
    ; the controller always keeps to the window it used last, so check that one first
    try if targetName = "Document" && (p := Integer(IniRead(ini, "State", "AppliedTo", 0))) && WinExist(p) && AppId(p) = DocId()
        return p
    best := 0
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
Top(h) => h && WinExist(h) && !!(WinGetExStyle(h) & 0x8)
Alpha(h) => h && WinExist(h) ? WinGetTransparent(h) : "n/a"
Dip(h, &w, &hh) {
    if !h || !WinExist(h) {
        w := hh := 0
        return
    }
    WinGetPos , , &pw, &ph, h
    sc := DllCall("GetDpiForWindow", "ptr", h, "uint") / 96
    w := Round(pw / sc), hh := Round(ph / sc)
}
Controller() {
    for h in WinGetList(dir "\GhostOverlay.ahk ahk_class AutoHotkey")
        return h
    return 0
}

; Ordinary Chrome windows (not the Document window): their alpha + topmost, to prove they are never touched.
RegularChrome() {
    m := Map()
    for h in WinGetList("ahk_exe chrome.exe ahk_class Chrome_WidgetWin_1")
        try if WinGetTitle(h) != "" && (WinGetStyle(h) & 0xC40000) = 0xC40000 && AppId(h) != DocId()
            m[h] := WinGetTransparent(h) "|" ((WinGetExStyle(h) & 0x8) ? 1 : 0)
    return m
}
chromeBefore := RegularChrome()

; ---- setup: config for this run, fresh state
IniWrite targetName, ini, "Overlay", "Target"
IniWrite 65, ini, "Overlay", "Opacity"
IniWrite 5, ini, "Overlay", "OpacityStep"
IniWrite 1, ini, "Overlay", "MinOpacity"
IniWrite 1, ini, "Overlay", "AlwaysOnTop"
RunWait '"' dir '\Stop-GhostOverlay.cmd"', , "Hide"
try IniDelete ini, "State"   ; after the stop: the old controller saves its state on exit
Run '"' dir '\Start-GhostOverlay.cmd"', , "Hide"
loop 40
    if Controller()
        break
    else Sleep 100
Check("controller starts", Controller())

probe := Gui("+ToolWindow", "GhostOverlay FocusProbe")
probe.Add("Text", , "focus probe")
probe.Show("x60 y60 w200 h60")
WinActivate probe.Hwnd
Sleep 400
Check("probe window has focus", WinActive(probe.Hwnd))

; ---- show
Hk("^!g", 2500)
h := 0
loop 120 {   ; allow up to 30 s for a cold app launch
    h := Target()
    if Vis(h) && Alpha(h) = 166
        break
    Sleep 250
}
Check("Ctrl+Alt+G shows ChatGPT window", Vis(h))
Check("shown window is active (has input focus)", WinActive(h))
Check("initial opacity 65% (alpha 166)", Alpha(h) = 166, "alpha=" Alpha(h))
Check("always-on-top enabled", Top(h))
Dip(h, &w, &hh)
Check("size ~430x550 DIP (or app minimum)", (Abs(w - 430) <= 2 && Abs(hh - 550) <= 2) || (w < 700 && hh < 800), w "x" hh " DIP, dpi=" DllCall("GetDpiForWindow", "ptr", h, "uint"))
Check("window is resizable + movable (caption + sizing frame)", (WinGetStyle(h) & 0xC40000) = 0xC40000)
mon := DllCall("MonitorFromWindow", "ptr", h, "uint", 0, "ptr")
Check("window is on a monitor", mon != 0)

; ---- transparency
Hk("{Ctrl down}{Alt down}{Up}{Alt up}{Ctrl up}")
Check("Ctrl+Alt+Up -> 70% (179)", Alpha(h) = 179, "alpha=" Alpha(h))
Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}"), Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}")
Check("Ctrl+Alt+Down x2 -> 60% (153)", Alpha(h) = 153, "alpha=" Alpha(h))
loop 11
    Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 120)
Sleep 400
Check("Ctrl+Alt+Down x11 -> 5% (13)", Alpha(h) = 13, "alpha=" Alpha(h))
Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 400)
Check("next Ctrl+Alt+Down -> exactly 1% (3)", Alpha(h) = 3, "alpha=" Alpha(h))
Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 400)
Check("opacity floor 1% (3), never 0 / invisible", Alpha(h) = 3, "alpha=" Alpha(h))
Sleep 400
Check("1% saved to config", IniRead(ini, "Overlay", "Opacity") = 1, "ini=" IniRead(ini, "Overlay", "Opacity"))
Hk("{Ctrl down}{Alt down}{Up}{Alt up}{Ctrl up}", 400)
Check("Ctrl+Alt+Up from 1% -> 5% (13)", Alpha(h) = 13, "alpha=" Alpha(h))
Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 400)
loop 21   ; 1 -> 5 -> ... -> 100, plus one extra press at the ceiling
    Hk("{Ctrl down}{Alt down}{Up}{Alt up}{Ctrl up}", 120)
Sleep 400
Check("opacity 100% removes transparency", Alpha(h) = "", "alpha=" Alpha(h))
loop 7
    Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 120)
Sleep 400
Check("back to 65% (166)", Alpha(h) = 166, "alpha=" Alpha(h))
Check("opacity persisted to config", IniRead(ini, "Overlay", "Opacity") = 65)

; ---- Document Mode: the exact levels asked for, on the real Chrome app window
if targetName = "Document" {
    Check("Document window carries the ChatGPT app identity", AppId(h) = DocId())
    loop 7   ; 65 -> 30
        Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 120)
    Sleep 400
    Check("Document: 30% (alpha 77)", Alpha(h) = 77, "alpha=" Alpha(h))
    loop 4   ; 30 -> 10
        Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 120)
    Sleep 400
    Check("Document: 10% (alpha 26)", Alpha(h) = 26, "alpha=" Alpha(h))
    loop 2   ; 10 -> 5 -> 1
        Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 120)
    Sleep 400
    Check("Document: 1% (alpha 3)", Alpha(h) = 3, "alpha=" Alpha(h))
    loop 20  ; 1 -> 5 -> ... -> 100
        Hk("{Ctrl down}{Alt down}{Up}{Alt up}{Ctrl up}", 120)
    Sleep 400
    Check("Document: 100% (opaque)", Alpha(h) = "", "alpha=" Alpha(h))
    loop 7   ; 100 -> 65
        Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 120)
    Sleep 400
    Check("Document: back to 65% (166)", Alpha(h) = 166, "alpha=" Alpha(h))
    changed := 0
    for hc, st in RegularChrome()
        if chromeBefore.Has(hc) && chromeBefore[hc] != st
            changed++
    Check("ordinary Chrome windows untouched", changed = 0, chromeBefore.Count " checked, " changed " changed")
}

; ---- always on top
Hk("^!t")
Check("Ctrl+Alt+T turns always-on-top OFF", !Top(h))
Hk("^!t")
Check("Ctrl+Alt+T turns always-on-top ON", Top(h))

; ---- move / resize persistence
WinGetPos &x0, &y0, , , h
WinMove x0 - 100, y0 - 80, , , h
Sleep 300
WinGetPos &mx, &my, , , h
Hk("^!g", 900)
Check("Ctrl+Alt+G hides window", !Vis(h))
Check("focus restored to previous window after hide", WinActive(probe.Hwnd), "active=" WinGetTitle("A"))
Hk("^!g", 1500)
WinGetPos &x1, &y1, , , h
Check("Ctrl+Alt+G shows again, same window", Vis(h) && Target() = h)
Check("moved position kept across hide/show", x1 = mx && y1 = my, x1 "," y1 " vs " mx "," my)
Check("styling kept after re-show", Alpha(h) = 166 && Top(h))

; ---- drift recovery: something else strips our styling
WinSetTransparent "Off", h
WinSetAlwaysOnTop 0, h
Sleep 2200
Check("watchdog re-applies opacity/topmost", Alpha(h) = 166 && Top(h), "alpha=" Alpha(h) " top=" Top(h))

; ---- emergency reset from a broken state (off-screen + 1 % opacity + hidden)
loop 14   ; 65 -> 5 -> 1, plus one press at the floor
    Hk("{Ctrl down}{Alt down}{Down}{Alt up}{Ctrl up}", 120)
Sleep 400
Check("at 1% before emergency test (3)", Alpha(h) = 3, "alpha=" Alpha(h))
WinMove -9000, -9000, , , h
Hk("^!g", 900)
Hk("^!+r", 2500)
h := Target()
WinGetPos &rx, &ry, &rw, &rh, h
MonitorGetWorkArea MonitorGetPrimary(), &l, &t, &r, &b
Check("Ctrl+Alt+Shift+R: visible", Vis(h))
Check("Ctrl+Alt+Shift+R: fully opaque", Alpha(h) = "", "alpha=" Alpha(h))
Check("Ctrl+Alt+Shift+R: back on primary screen", rx >= l && ry >= t && rx + rw <= r && ry + rh <= b, rx "," ry " " rw "x" rh)
Check("Ctrl+Alt+Shift+R: focused", WinActive(h))
Sleep 1800
Check("reset 100% is not undone by the watchdog", Alpha(h) = "", "alpha=" Alpha(h))
Check("reset does not overwrite saved opacity (1)", IniRead(ini, "Overlay", "Opacity") = 1, "ini=" IniRead(ini, "Overlay", "Opacity"))
Hk("^!g", 900)
Check("hide after reset", !Vis(h))
Hk("^!g", 1500)
Check("reopen after reset restores saved 1% (3)", Vis(h) && Alpha(h) = 3, "alpha=" Alpha(h))
loop 13   ; 1 -> 5 -> ... -> 65
    Hk("{Ctrl down}{Alt down}{Up}{Alt up}{Ctrl up}", 120)
Sleep 400
Check("opacity back to 65% after reset", Alpha(h) = 166, "alpha=" Alpha(h))

; ---- controller crash + restart keeps working
ProcessClose WinGetPID(Controller())
Sleep 500
Check("controller killed (simulated crash)", !Controller())
Run '"' dir '\Start-GhostOverlay.cmd"', , "Hide"
Sleep 2000
Check("controller restarted", Controller())
Check("window still styled after controller restart", Alpha(h) = 166 && Top(h))
Hk("^!g", 900)
Check("hotkeys work after controller restart (hide)", !Vis(h))
Hk("^!g", 1500)
Check("hotkeys work after controller restart (show + focus)", Vis(h) && WinActive(h))
; window hidden by the previous controller instance must re-show cleanly
Hk("^!g", 900)
ProcessClose WinGetPID(Controller())
Sleep 500
Run '"' dir '\Start-GhostOverlay.cmd"', , "Hide"
Sleep 2000
Hk("^!g", 1500)
Check("re-show of window hidden by previous instance", Vis(h) && Alpha(h) = 166)

; ---- second instance is refused
Run '"' dir '\Start-GhostOverlay.cmd"', , "Hide"
Sleep 4500
n := 0
for c in WinGetList(dir "\GhostOverlay.ahk ahk_class AutoHotkey")
    n++
Check("single instance enforced", n = 1, n " instances")

; ---- app restart recovery
if doRestart {
    pid := WinGetPID(h)
    ProcessClose pid
    for p in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, ExecutablePath from Win32_Process")
        try if InStr(p.ExecutablePath, pathPart)
            ProcessClose p.ProcessId
    Sleep 1500
    Check("target app terminated", !Target())
    ; Relaunch the app the way a user would (Start menu). Some apps cold-start to the tray,
    ; so open it again until its window is visible - the controller must not be involved.
    deadline := A_TickCount + 40000, lastRun := 0
    while A_TickCount < deadline && !(Vis(Target()) && Alpha(Target()) = 166) {
        if !Vis(Target()) && A_TickCount - lastRun > 5000 {
            Run 'explorer.exe "shell:AppsFolder\' aumid '"'
            lastRun := A_TickCount
        }
        Sleep 250
    }
    h2 := Target()
    Check("app restarted with new window", h2 && h2 != h)
    Check("overlay re-attached automatically (opacity+topmost)", Alpha(h2) = 166 && Top(h2), "alpha=" Alpha(h2))
    Dip(h2, &w2, &hh2)
    Check("size restored after app restart", w2 < 700 && hh2 < 800, w2 "x" hh2 " DIP")
    h := h2
}

; ---- resource usage (idle 30 s)
cpid := WinGetPID(Controller())
GetTimes(pid) {
    hp := DllCall("OpenProcess", "uint", 0x1000, "int", 0, "uint", pid, "ptr")
    c := Buffer(8), e := Buffer(8), k := Buffer(8), u := Buffer(8)
    DllCall("GetProcessTimes", "ptr", hp, "ptr", c, "ptr", e, "ptr", k, "ptr", u)
    pm := Buffer(80, 0), NumPut("uint", 80, pm)
    DllCall("psapi\GetProcessMemoryInfo", "ptr", hp, "ptr", pm, "uint", 80)
    DllCall("CloseHandle", "ptr", hp)
    return {cpu: (NumGet(k, "int64") + NumGet(u, "int64")) / 10000, ws: NumGet(pm, 16, "uptr") / 1048576, priv: NumGet(pm, 72, "uptr") / 1048576}
}
t0 := GetTimes(cpid)
Sleep 30000
t1 := GetTimes(cpid)
cpuPct := (t1.cpu - t0.cpu) / 30000 * 100 / EnvGet("NUMBER_OF_PROCESSORS")
Check("idle CPU < 0.1%", cpuPct < 0.1, Format("{:.4f}% over 30 s ({} ms CPU)", cpuPct, Round(t1.cpu - t0.cpu)))
Check("memory < 25 MB", t1.ws < 25, Format("working set {:.1f} MB, private {:.1f} MB", t1.ws, t1.priv))

; ---- stop launcher restores the window
RunWait '"' dir '\Stop-GhostOverlay.cmd"', , "Hide"
Sleep 600
Check("Stop launcher ends controller", !Controller())
Check("window restored: opaque", Alpha(h) = "", "alpha=" Alpha(h))
Check("window restored: not always-on-top", !Top(h))
Check("window restored: visible", Vis(h))

changed := 0
for hc, st in RegularChrome()
    if chromeBefore.Has(hc) && chromeBefore[hc] != st
        changed++
Check("ordinary Chrome windows untouched by the whole run", changed = 0, chromeBefore.Count " checked, " changed " changed")
probe.Destroy()
FileAppend Format("`n{}: {} passed, {} failed`n", targetName, pass, fail) out, "*"
ExitApp fail ? 1 : 0
