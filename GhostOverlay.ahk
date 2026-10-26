; ChatGPT Ghost Overlay - local window controller for the official ChatGPT Windows app.
; It only moves/resizes/fades/shows/hides the app's own window through standard Win32 calls.
; It never reads app data, credentials, or network traffic, and never modifies the app.
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
Persistent
KeyHistory 0
ListLines false
SetWinDelay 0
DetectHiddenWindows true

; Per-monitor-v2 DPI awareness so all coordinates are physical pixels on every monitor.
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

global CFG := A_ScriptDir "\GhostOverlay.ini"
global LOGFILE := A_ScriptDir "\GhostOverlay.log"

; Known official Store packages (publisher OpenAI, family suffix 2p2nqsd0c76g0).
global TARGETS := Map(
    "ChatGPT", {kind: "app", aumid: "OpenAI.Codex_2p2nqsd0c76g0!App", pathPart: "\OpenAI.Codex_", title: "^ChatGPT$"},
    "Classic", {kind: "app", aumid: "OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT", pathPart: "\OpenAI.ChatGPT-Desktop_", title: "^ChatGPT Classic$"},
    ; Document Mode: chatgpt.com in Chrome's app-style window, styled by DocumentMode\extension.
    ; Chrome gives that window its own Windows app ID, derived from DocUrl and DocProfile (see
    ; DocAppIdMatches), which is how it is told apart from ordinary Chrome windows and from app
    ; windows opened on other addresses (titles change with the conversation, so they are not used).
    "Document", {kind: "browser", aumid: "", pathPart: "\chrome.exe", title: ""}
)

global S := {}            ; settings from [Overlay]
global T := ""            ; active target descriptor
global hTarget := 0       ; cached target hwnd
global appliedTo := 0     ; hwnd the overlay styling was applied to
global primary := 0       ; window this controller used last time (kept across restarts)
global engaged := false   ; true once the user has summoned the overlay
global hiddenByUs := 0    ; hwnd we hid (safe to WinShow directly)
global prevFocus := 0     ; window to give focus back to on hide
global orig := 0          ; original placement of the window before takeover
global geo := 0           ; last overlay geometry {x, y, w, h(DIP)}, written to disk lazily
global busy := false
global opacityDirty := false   ; an opacity change is waiting to be written
global rescue := false    ; emergency reset in effect: shown at 100 % without touching the saved Opacity
global atLogin := A_Args.Length && A_Args[1] = "--startup"   ; launched by the Startup shortcut

if A_Args.Length && A_Args[1] = "--init-config" {   ; installer: write the default config only
    if !FileExist(CFG)
        WriteDefaultConfig()
    ExitApp
}
HandleSingleInstance()
LoadConfig()
RestoreState()
SetupTray()

Hotkey "^!g", (*) => ToggleOverlay(), "B"   ; B = queue a press that arrives mid-toggle instead of dropping it
Hotkey "^!Up", (*) => AdjustOpacity(+S.OpacityStep), "B"
Hotkey "^!Down", (*) => AdjustOpacity(-S.OpacityStep), "B"
Hotkey "^!t", (*) => ToggleTopmost(), "B"
Hotkey "^!+r", (*) => EmergencyReset()

OnExit(Cleanup)
SetTimer Watch, S.WatchIntervalMs
if S.PrewarmOnStartup && !engaged
    SetTimer Prewarm, 2000
Log("started" (atLogin ? " at login" : "") "; target=" S.Target " opacity=" S.Opacity " topmost=" S.AlwaysOnTop)

; ---------------------------------------------------------------- startup

HandleSingleInstance() {
    others := []
    for h in WinGetList(A_ScriptFullPath " ahk_class AutoHotkey")
        if h != A_ScriptHwnd
            others.Push(h)
    switching := A_Args.Length >= 2 && A_Args[1] = "--mode"
    if switching {   ; --mode <Target>: save the presentation mode, then replace the running copy
        if !TARGETS.Has(A_Args[2]) {
            MsgBox "Unknown mode '" A_Args[2] "'. Use Document, ChatGPT or Classic.", "Ghost Overlay", "Icon!"
            ExitApp
        }
        IniWrite A_Args[2], CFG, "Overlay", "Target"
    }
    if switching || (A_Args.Length && A_Args[1] = "--stop") {
        for h in others
            PostMessage 0x10, 0, 0, , h   ; WM_CLOSE -> clean exit with restore
        for h in others
            WinWaitClose h, , 5
        if !switching
            ExitApp
        others := []
    }
    ; Named mutex closes the race where two copies start at the same instant (e.g. login).
    ; When switching modes the old copy may still be finishing its exit: wait for it (max 5 s).
    loop switching ? 25 : 1 {
        hm := DllCall("CreateMutex", "ptr", 0, "int", 0, "str", "Local\ChatGPTGhostOverlay", "ptr")
        if A_LastError != 183 || A_Index = (switching ? 25 : 1)
            break
        DllCall("CloseHandle", "ptr", hm)
        Sleep 200
    }
    if others.Length || A_LastError = 183 {   ; ERROR_ALREADY_EXISTS
        if !atLogin
            MsgBox "ChatGPT Ghost Overlay is already running.", "Ghost Overlay", "Iconi T3"
        ExitApp
    }
}

; Prepare the ChatGPT window in advance (sized, styled, hidden) so the first Ctrl+Alt+G is
; instant. Never launches ChatGPT itself; waits for the app's own startup instead.
Prewarm() {
    static deadline := A_TickCount + 180000
    global engaged, appliedTo, hiddenByUs, orig
    if engaged || A_TickCount > deadline {
        SetTimer Prewarm, 0
        return
    }
    if busy
        return
    h := FindTarget()
    if !h
        return
    SetTimer Prewarm, 0
    visible := DllCall("IsWindowVisible", "ptr", h)
    if visible && !atLogin
        return   ; user is using ChatGPT as a normal window right now: leave it alone
    prev := WinExist("A")
    RecordOrig(h)
    if !visible {
        ; App is in the tray. Let it show the window fully transparent, then hide it again.
        WinSetTransparent 0, h
        if T.kind = "browser"
            WinShow h   ; Chrome repaints a re-shown window normally (only Electron needs activation)
        else if !ActivateApp() {
            WinSetTransparent "Off", h
            Log("prewarm: app did not show its window")
            return
        }
    }
    if WinGetMinMax(h) != 0
        WinRestore h
    PlaceWindow(h)
    EnsureOnScreen(h)
    WinSetAlwaysOnTop S.AlwaysOnTop, h
    WinHide h
    ApplyOpacity(h)   ; real opacity is in place for the next show
    appliedTo := h, hiddenByUs := h, engaged := true
    SaveSoon()
    if prev && prev != h && WinExist(prev) && IsShown(prev)
        try WinActivate prev
    Log("prewarmed " Format("{:#x}", h) (atLogin ? " at login" : ""))
}

LoadConfig() {
    global S, T
    if !FileExist(CFG)
        WriteDefaultConfig()
    r(key, def) => IniRead(CFG, "Overlay", key, def)
    S.Target          := r("Target", "ChatGPT")
    S.Width           := Integer(r("Width", 430))
    S.Height          := Integer(r("Height", 550))
    S.Opacity         := Integer(r("Opacity", 30))
    S.OpacityStep     := Clamp(Integer(r("OpacityStep", 5)), 1, 50)
    S.MinOpacity      := Clamp(Integer(r("MinOpacity", 1)), 1, 100)   ; 1 % floor: never fully invisible
    S.AlwaysOnTop     := Integer(r("AlwaysOnTop", 1))
    S.Margin          := Integer(r("Margin", 24))
    S.LaunchIfMissing := Integer(r("LaunchIfMissing", 1))
    S.LaunchTimeoutMs := Integer(r("LaunchTimeoutMs", 25000))
    S.RestoreOnExit   := Integer(r("RestoreOnExit", 1))
    S.WatchIntervalMs := Max(500, Integer(r("WatchIntervalMs", 1500)))
    S.ShowTips        := Integer(r("ShowTips", 1))
    S.PrewarmOnStartup := Integer(r("PrewarmOnStartup", 1))
    S.DocBrowser      := r("DocBrowser", "")    ; blank = find chrome.exe automatically
    S.DocProfile      := r("DocProfile", "")    ; Chrome profile folder, e.g. "Profile 1"; blank = last used
    S.DocUrl          := r("DocUrl", "https://chatgpt.com/")
    S.Opacity := Clamp(S.Opacity, S.MinOpacity, 100)
    if !TARGETS.Has(S.Target)
        S.Target := "ChatGPT"
    T := TARGETS[S.Target]
}

WriteDefaultConfig() {
    FileAppend "
    (
; ChatGPT Ghost Overlay configuration. Edit, then use tray menu > Reload (or restart).
; Width/Height are in DPI-independent pixels (scaled automatically for Windows display scaling).
; Target: ChatGPT = current ChatGPT app (Store package OpenAI.Codex)
;         Classic = ChatGPT Classic (Store package OpenAI.ChatGPT-Desktop)
;         Document = chatgpt.com in a Chrome app window with the Document Mode look (see README)
; DocBrowser / DocProfile / DocUrl are only used by Target=Document.
[Overlay]
Target=ChatGPT
Width=430
Height=550
Opacity=30
OpacityStep=5
MinOpacity=1
AlwaysOnTop=1
Margin=24
LaunchIfMissing=1
LaunchTimeoutMs=25000
RestoreOnExit=1
WatchIntervalMs=1500
ShowTips=1
PrewarmOnStartup=1
DocBrowser=
DocProfile=
DocUrl=https://chatgpt.com/

; Runtime state written by the controller. Safe to delete.
[State]
    )", CFG, "UTF-8"
}

RestoreState() {
    global engaged, appliedTo, hiddenByUs, orig
    rd(key) => IniRead(CFG, "State", key, "")
    h := Integer(rd("AppliedTo") || 0)
    if h && IsTargetWindow(h)
        global primary := h   ; even after a clean exit, prefer this window over any other match
    if Integer(rd("Engaged") || 0) && h && IsTargetWindow(h) {
        engaged := true
        appliedTo := h
        hiddenByUs := (Integer(rd("HiddenByUs") || 0) = h) ? h : 0
        if Integer(rd("OrigHwnd") || 0) = h {
            o := {hwnd: h, x: Integer(rd("OrigX")), y: Integer(rd("OrigY")), w: Integer(rd("OrigW")), h: Integer(rd("OrigH"))}
            if ValidRect(o.x, o.y, o.w, o.h)   ; ignore a bad (minimized/off-screen) record
                orig := o
        }
        if DllCall("IsWindowVisible", "ptr", h)
            ApplyStyle(h)
    }
}

SaveState() {
    IniWrite engaged ? 1 : 0, CFG, "State", "Engaged"
    IniWrite appliedTo, CFG, "State", "AppliedTo"
    IniWrite hiddenByUs, CFG, "State", "HiddenByUs"
}

; All [State] disk writes go through here, deferred so show/hide never waits on the disk
; (a hotkey arriving while its handler is still busy would otherwise be lost).
Persist() {
    if IsObject(geo) {
        IniWrite geo.x, CFG, "State", "LastX"
        IniWrite geo.y, CFG, "State", "LastY"
        IniWrite geo.w, CFG, "State", "LastW"
        IniWrite geo.h, CFG, "State", "LastH"
    }
    if IsObject(orig) {
        for k, v in Map("OrigX", orig.x, "OrigY", orig.y, "OrigW", orig.w, "OrigH", orig.h)
            IniWrite v, CFG, "State", k
    }
    IniWrite IsObject(orig) ? orig.hwnd : 0, CFG, "State", "OrigHwnd"
    SaveState()
}
SaveSoon() => SetTimer(Persist, -250)

; Remember where the window was before takeover, but only a normal, on-screen placement.
RecordOrig(h) {
    global orig
    loop 30   ; WinRestore can take a moment to leave the minimized state
        if WinGetMinMax(h) != -1
            break
        else Sleep 10
    WinGetPos &x, &y, &w, &hh, h
    if ValidRect(x, y, w, hh) {
        orig := {hwnd: h, x: x, y: y, w: w, h: hh}
        Log("attached to " Format("{:#x}", h) " orig=" w "x" hh "@" x "," y)
    } else {
        orig := 0
        Log("attached to " Format("{:#x}", h) " (window was minimized/off-screen; original placement not recorded)")
    }
}

ValidRect(x, y, w, h) {
    if x <= -30000 || y <= -30000 || w < 100 || h < 100   ; -32000 = minimized placeholder
        return false
    r := Buffer(16)
    NumPut("int", x, "int", y, "int", x + w, "int", y + h, r)
    return DllCall("MonitorFromRect", "ptr", r, "uint", 0, "ptr") != 0   ; on some monitor
}

SetupTray() {
    A_IconHidden := false
    A_IconTip := "ChatGPT Ghost Overlay"
    m := A_TrayMenu
    m.Delete()
    m.Add("Show / Hide`tCtrl+Alt+G", (*) => ToggleOverlay())
    m.Add("Toggle always-on-top`tCtrl+Alt+T", (*) => ToggleTopmost())
    m.Add("Emergency reset`tCtrl+Alt+Shift+R", (*) => EmergencyReset())
    m.Add()
    for name, label in Map("Document", "Mode: Document (Chrome app window)", "ChatGPT", "Mode: native ChatGPT app") {
        m.Add(label, SwitchMode.Bind(name))
        if S.Target = name
            m.Check(label)
    }
    m.Add()
    m.Add("Open config", (*) => Run('notepad.exe "' CFG '"'))
    m.Add("Reload config", (*) => Reload())
    m.Add("Exit (restore ChatGPT window)", (*) => ExitApp())
    m.Default := "Show / Hide`tCtrl+Alt+G"
}

; A fresh copy saves the new mode and replaces this one (this copy hands its window back on exit).
SwitchMode(name, *) {
    if name != S.Target
        Run '"' A_AhkPath '" "' A_ScriptFullPath '" --mode ' name
}

; ---------------------------------------------------------------- window discovery

IsTargetWindow(h) {
    try {
        if WinGetClass(h) != "Chrome_WidgetWin_1"
            return false
        path := WinGetProcessPath(h)
        if !InStr(path, T.pathPart)
            return false
        if T.kind = "browser" {
            if (exe := ChromePath()) != "" && path != exe
                return false   ; another Chrome install or channel
            if !DocAppIdMatches(WindowAppId(h))
                return false   ; an ordinary browser window, or an app window opened on another address
        }
        style := WinGetStyle(h), ex := WinGetExStyle(h)
        ; real top-level app window: caption + resizable frame, not a click-through layer
        return (style & 0xC40000) = 0xC40000 && !(ex & 0x20) && WinGetTitle(h) != ""
    }
    return false
}

FindTarget() {
    global hTarget
    ; The window we styled, then the one we used before a restart, always win over any other
    ; matching window, so a second window can never take the overlay over while ours exists.
    for h in [appliedTo, primary, hTarget]
        if h && WinExist(h) && IsTargetWindow(h)
            return hTarget := h
    fallback := 0, shown := 0, n := 0
    for h in WinGetList("ahk_class Chrome_WidgetWin_1") {
        if !IsTargetWindow(h)
            continue
        if T.title != "" && RegExMatch(WinGetTitle(h), T.title)
            return hTarget := h
        n++
        fallback := fallback || h
        if !shown && DllCall("IsWindowVisible", "ptr", h)
            shown := h
    }
    if n > 1
        Log(n " matching windows; using " Format("{:#x}", shown || fallback))
    return hTarget := shown || fallback
}

; Whether a Windows app ID is the one Chrome gives the window it opens for --app=DocUrl in
; DocProfile. Chrome builds it as "Chrome.<host>_<path>[.<user data dir>.<profile>]" (no profile
; part for "Default"), cutting each part longer than its share of 64 characters down to its
; first and last halves: https://chatgpt.com/ in "Profile 1" -> "Chrome.chatgpt.com_/.UserData.Profile1",
; a long deep link -> "Chrome.chatgpt.co" + its last 10 characters + ".UserData.Profile1".
DocAppIdMatches(id) {
    static app := ""
    if app = "" {
        u := RegExReplace(RegExReplace(S.DocUrl, "^[a-zA-Z][\w+.-]*://"), "[?#].*")
        p := InStr(u, "/")
        app := RegExReplace(StrLower(p ? SubStr(u, 1, p - 1) : u), ":\d+$") "_" (p ? SubStr(u, p) : "/")
    }
    cut(s, n) => StrLen(s) > n ? SubStr(s, 1, n // 2) SubStr(s, -((n + 1) // 2)) : s
    if S.DocProfile = "Default" || S.DocProfile = ""
        if id = "Chrome." cut(app, 31)   ; two parts: (64 - 1) // 2 characters each
            return true
    if S.DocProfile = "Default"
        return false
    prof := S.DocProfile = "" ? "[A-Za-z0-9.]+" : "\Q" RegExReplace(S.DocProfile, "[^A-Za-z0-9.]") "\E"
    return RegExMatch(id, "^\QChrome." cut(app, 20) "\E\.UserData\." prof "$")   ; three parts: (64 - 2) // 3
}

IsShown(h) => h && DllCall("IsWindowVisible", "ptr", h) && WinGetMinMax(h) != -1

; The Windows app ID (System.AppUserModel.ID) a window carries; "" if it has none.
WindowAppId(h) {
    static iid := 0, key := 0
    if !iid {
        iid := Buffer(16), key := Buffer(20)
        DllCall("ole32\CLSIDFromString", "str", "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}", "ptr", iid)   ; IPropertyStore
        DllCall("ole32\CLSIDFromString", "str", "{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}", "ptr", key)   ; PKEY_AppUserModel_ID
        NumPut("uint", 5, key, 16)
    }
    ps := 0, pv := Buffer(24, 0), id := ""
    if DllCall("shell32\SHGetPropertyStoreForWindow", "ptr", h, "ptr", iid, "ptr*", &ps) != 0 || !ps
        return ""
    try {
        ComCall(5, ps, "ptr", key, "ptr", pv)   ; IPropertyStore::GetValue
        if NumGet(pv, 0, "ushort") = 31          ; VT_LPWSTR
            id := StrGet(NumGet(pv, 8, "ptr"))
    }
    DllCall("ole32\PropVariantClear", "ptr", pv)
    ObjRelease(ps)
    return id
}

ChromePath() {
    if S.DocBrowser != "" && FileExist(S.DocBrowser)
        return S.DocBrowser
    for p in [A_ProgramFiles "\Google\Chrome\Application\chrome.exe"
            , EnvGet("ProgramFiles(x86)") "\Google\Chrome\Application\chrome.exe"
            , EnvGet("LOCALAPPDATA") "\Google\Chrome\Application\chrome.exe"]
        if FileExist(p)
            return p
    return ""
}

; Start (or ask for) the target's window: the Store app's official activation, or for
; Document Mode one Chrome app window on chatgpt.com in the configured profile.
LaunchTarget() {
    if T.kind != "browser" {
        Run 'explorer.exe "shell:AppsFolder\' T.aumid '"'
        return true
    }
    exe := ChromePath()
    if exe = "" {
        Tip("Chrome not found (set DocBrowser in the config)")
        Log("document mode: chrome.exe not found")
        return false
    }
    Run '"' exe '"' (S.DocProfile != "" ? ' --profile-directory="' S.DocProfile '"' : "") ' --app=' S.DocUrl
    return true
}

; Ask the app itself to show its window (official activation). Needed when the app hid the
; window to its tray, because raw ShowWindow does not wake Electron's renderer.
ActivateApp() {
    Log("activating " (T.kind = "browser" ? "document window" : "app " T.aumid))
    if !LaunchTarget()
        return 0
    start := A_TickCount, lastAsk := start
    while A_TickCount - start < S.LaunchTimeoutMs {
        Sleep 250
        h := FindTarget()
        if IsShown(h) {
            Sleep 200   ; let the app finish restoring its own bounds
            return h
        }
        ; A cold start can leave the window in the tray; asking again shows it.
        ; (Never for Document Mode: each launch would open another Chrome window.)
        if h && T.kind != "browser" && A_TickCount - lastAsk > 5000 {
            Run 'explorer.exe "shell:AppsFolder\' T.aumid '"'
            lastAsk := A_TickCount
        }
    }
    return 0
}

; ---------------------------------------------------------------- core actions

ToggleOverlay() {
    global rescue := false   ; any normal show/hide returns to the saved opacity
    h := FindTarget()
    ; A window that is not the overlay yet (e.g. opened directly from Chrome) is taken over, not hidden.
    if IsShown(h) && h = appliedTo && (WinActive(h) || (WinGetExStyle(h) & 0x8))
        HideOverlay(h)
    else
        ShowOverlay()
}

ShowOverlay(forceDefaultPlacement := false) {
    global busy, engaged, appliedTo, hiddenByUs, prevFocus, orig
    if busy
        return
    busy := true
    try {
        active := WinExist("A")
        h := FindTarget()
        if active && active != h
            prevFocus := active
        viaApp := false
        if !h || (!DllCall("IsWindowVisible", "ptr", h) && h != hiddenByUs && T.kind != "browser") {
            if !h && !S.LaunchIfMissing {
                Tip("ChatGPT window not found")
                return
            }
            h := ActivateApp()
            if !h {
                Tip("ChatGPT did not open in time")
                Log("activation timed out")
                return
            }
            viaApp := true
        } else if !DllCall("IsWindowVisible", "ptr", h) {
            WinShow h
        }
        if WinGetMinMax(h) != 0
            WinRestore h
        isNew := (h != appliedTo)
        if isNew
            RecordOrig(h)
        if isNew || viaApp || forceDefaultPlacement
            PlaceWindow(h, forceDefaultPlacement)
        ApplyStyle(h)
        EnsureOnScreen(h)
        appliedTo := h, hiddenByUs := 0, engaged := true
        WinActivate h
        SaveSoon()
    } finally busy := false
}

HideOverlay(h) {
    global hiddenByUs
    wasActive := WinActive(h)
    CaptureGeometry(h)
    WinHide h
    ApplyOpacity(h)   ; next show starts at the saved opacity (ends an emergency 100 %)
    hiddenByUs := h
    if wasActive && prevFocus && prevFocus != h && WinExist(prevFocus) && IsShown(prevFocus)
        try WinActivate prevFocus
    SaveSoon()
}

AdjustOpacity(delta) {
    global rescue := false   ; adjust from the saved value, not from the temporary 100 %
    ; Move along the step grid (... 10, 5, then the floor): 5 % down -> 1 %, 1 % up -> 5 %.
    st := Abs(delta)
    next := delta > 0 ? (S.Opacity // st + 1) * st : ((S.Opacity - 1) // st) * st
    S.Opacity := Clamp(next, S.MinOpacity, 100)
    global opacityDirty := true
    SetTimer SaveOpacity, -300   ; write once after the presses settle; never block a keypress on disk
    h := FindTarget()
    if h && (h = appliedTo || Adopt(h))
        ApplyOpacity(h)
    Tip("Opacity " S.Opacity "%")
}

SaveOpacity() {
    global opacityDirty := false
    IniWrite S.Opacity, CFG, "Overlay", "Opacity"
    Log("opacity saved: " S.Opacity "% (Ctrl+Alt+Up/Down)")
}

ToggleTopmost() {
    S.AlwaysOnTop := !S.AlwaysOnTop
    IniWrite S.AlwaysOnTop, CFG, "Overlay", "AlwaysOnTop"
    h := FindTarget()
    if h && (h = appliedTo || Adopt(h))
        WinSetAlwaysOnTop S.AlwaysOnTop, h
    Tip("Always on top: " (S.AlwaysOnTop ? "ON" : "OFF"))
}

; The opacity / topmost keys also take over a target window the user opened directly (e.g. the
; Document window launched from Chrome) instead of only one summoned with Ctrl+Alt+G.
; It is styled where it is; nothing is moved or resized.
Adopt(h) {
    global appliedTo, engaged, hiddenByUs
    if busy || !IsShown(h)
        return false
    RecordOrig(h)
    appliedTo := h, hiddenByUs := 0, engaged := true
    ApplyStyle(h)
    SaveSoon()
    Log("adopted " Format("{:#x}", h))
    return true
}

EmergencyReset() {
    global hTarget, rescue
    rescue := true   ; temporary 100 %; the saved Opacity is left alone
    global geo := 0
    for k in ["LastX", "LastY", "LastW", "LastH"]
        try IniDelete CFG, "State", k
    hTarget := 0   ; force a fresh window search
    ShowOverlay(true)
    Tip("Overlay reset: fully visible until hidden (saved " S.Opacity "% kept)")
    Log("emergency reset (temporary 100%, saved " S.Opacity "%)")
}

; ---------------------------------------------------------------- styling & geometry

ApplyStyle(h) {
    ApplyOpacity(h)
    WinSetAlwaysOnTop S.AlwaysOnTop, h
}

CurOpacity() => rescue ? 100 : S.Opacity
Alpha255(pct) => Max(1, Round(pct * 2.55))   ; 1 % -> 3, 5 % -> 13, 30 % -> 77; never 0 (invisible)

ApplyOpacity(h) {
    if CurOpacity() >= 100
        WinSetTransparent "Off", h
    else
        WinSetTransparent Alpha255(CurOpacity()), h
}

DpiScale(h) => DllCall("GetDpiForWindow", "ptr", h, "uint") / 96

PlaceWindow(h, useDefault := false) {
    if IsObject(geo)   ; newest geometry may not be on disk yet
        lx := geo.x, ly := geo.y, lw := geo.w, lh := geo.h
    else {
        lx := IniRead(CFG, "State", "LastX", ""), ly := IniRead(CFG, "State", "LastY", "")
        lw := IniRead(CFG, "State", "LastW", ""), lh := IniRead(CFG, "State", "LastH", "")
    }
    if !useDefault && lx != "" && ly != "" {
        WinMove Integer(lx), Integer(ly), , , h
        sc := DpiScale(h)   ; DPI of the monitor the window landed on
        WinMove , , Round((lw != "" ? lw : S.Width) * sc), Round((lh != "" ? lh : S.Height) * sc), h
        return
    }
    MonitorGetWorkArea MonitorGetPrimary(), &l, &t, &r, &b
    WinMove l + 50, t + 50, , , h          ; move onto the primary monitor first
    sc := DpiScale(h)
    WinMove , , Round(S.Width * sc), Round(S.Height * sc), h
    WinGetPos , , &w, &hh, h              ; app may enforce a larger minimum size
    m := Round(S.Margin * sc)
    WinMove r - w - m, b - hh - m, , , h
}

CaptureGeometry(h) {
    global geo
    if !IsShown(h) || WinGetMinMax(h) != 0
        return
    WinGetPos &x, &y, &w, &hh, h
    if !ValidRect(x, y, w, hh)
        return
    sc := DpiScale(h)
    geo := {x: x, y: y, w: Round(w / sc), h: Round(hh / sc)}
}

; Keep the window fully inside the work area of the nearest monitor (handles unplugged displays).
EnsureOnScreen(h) {
    WinGetPos &x, &y, &w, &hh, h
    mon := DllCall("MonitorFromWindow", "ptr", h, "uint", 2, "ptr")
    mi := Buffer(40, 0), NumPut("uint", 40, mi)
    DllCall("GetMonitorInfo", "ptr", mon, "ptr", mi)
    l := NumGet(mi, 20, "int"), t := NumGet(mi, 24, "int"), r := NumGet(mi, 28, "int"), b := NumGet(mi, 32, "int")
    nx := Max(l, Min(x, r - w)), ny := Max(t, Min(y, b - hh))
    if nx != x || ny != y
        WinMove nx, ny, , , h
}

; ---------------------------------------------------------------- watchdog (recovery)

Watch() {
    global appliedTo, hTarget
    if !engaged || busy
        return
    h := FindTarget()
    if !h
        return
    if h != appliedTo {
        ; The app restarted and created a new window: re-attach once it is visible.
        if DllCall("IsWindowVisible", "ptr", h) {
            Log("recovered: new window " Format("{:#x}", h))
            appliedTo := h
            PlaceWindow(h)
            ApplyStyle(h)
            EnsureOnScreen(h)
            SaveSoon()
        }
        return
    }
    if !DllCall("IsWindowVisible", "ptr", h)
        return
    ; Re-assert styling if the app reset it (cheap reads, writes only on drift).
    want := CurOpacity() >= 100 ? "" : Alpha255(CurOpacity())
    if WinGetTransparent(h) != want
        ApplyOpacity(h)
    if !!(WinGetExStyle(h) & 0x8) != !!S.AlwaysOnTop
        WinSetAlwaysOnTop S.AlwaysOnTop, h
}

; ---------------------------------------------------------------- exit

Cleanup(reason, code) {
    if opacityDirty
        SaveOpacity()   ; flush a pending deferred write (never overwrite the ini otherwise)
    h := appliedTo
    if !h || !WinExist(h) {
        Persist()
        return
    }
    CaptureGeometry(h)
    if reason = "Reload" || reason = "Logoff" || reason = "Shutdown" || !S.RestoreOnExit {
        Persist()
        return
    }
    Persist()
    ; Hand the window back to the user exactly as an ordinary ChatGPT window.
    WinSetTransparent "Off", h
    WinSetAlwaysOnTop 0, h
    if IsObject(orig) && orig.hwnd = h && ValidRect(orig.x, orig.y, orig.w, orig.h)
        WinMove orig.x, orig.y, orig.w, orig.h, h
    EnsureOnScreen(h)   ; never hand back a window that is off-screen
    if !DllCall("IsWindowVisible", "ptr", h)
        WinShow h
    IniWrite 0, CFG, "State", "Engaged"
    Log("exit (" reason "): window restored")
}

; ---------------------------------------------------------------- helpers

Clamp(v, lo, hi) => Max(lo, Min(hi, v))

Tip(msg) {
    if !S.ShowTips
        return
    ToolTip msg
    SetTimer () => ToolTip(), -1000
}

Log(msg) {
    line := FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n"
    loop 5 {   ; another process may have the log open for a moment: retry briefly
        try {
            if FileExist(LOGFILE) && FileGetSize(LOGFILE) > 262144
                FileDelete LOGFILE
            FileAppend line, LOGFILE, "UTF-8"
            return
        }
        Sleep 20
    }
}
