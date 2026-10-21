#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook
Persistent

; Roman2Hangul IME Bridge 0.2.5
; F9: switch between Ministry of Education 1959 orthographic mapping
;     and Ministry of Culture 2000 Revised Romanization mapping.
; F10: enable/disable. Enter: submit buffer without forwarding Enter.
; F8: toggle standalone Hangul letter mode (1959 rules, no syllable assembly).
; Windows Korean 2-beolsik IME must be active and in Hangul mode
; for normal conversion. Standalone mode inserts literal compatibility jamo.

SetKeyDelay(8, 8)

global BridgeOn := false
global RomanBuffer := ""
global BufferWindow := 0
global Mode := "MOE1959"
global JamoMode := false
global JamoPending := ""
global PhysicalLetters := ""
global Interceptor := InputHook("L0 I")

Loop 26
    PhysicalLetters .= "{vk" Format("{:02X}", 0x40 + A_Index) "}"

Interceptor.KeyOpt("{All}", "N")
Interceptor.KeyOpt(PhysicalLetters, "S")
Interceptor.KeyOpt("{vk20}{vk0D}{vk09}{vk08}", "S")
Interceptor.KeyOpt("{vkBD}{vkDE}", "S") ; - / ' for syllable boundaries
Interceptor.KeyOpt("{vkBE}{vkBC}{vkBF}{vkBA}", "S")
Loop 10
    Interceptor.KeyOpt("{vk" Format("{:02X}", 0x2F + A_Index) "}", "S")
Interceptor.OnKeyDown := ObserveDown
Interceptor.OnKeyUp := ObserveUp

TraySetIcon("shell32.dll", 44)
A_TrayMenu.Delete()
A_TrayMenu.Add("切换规范 (F9)", (*) => ToggleMode())
A_TrayMenu.Add("启用/关闭 (F10)", (*) => ToggleBridge())
A_TrayMenu.Add("独立字母模式 (F8)", (*) => ToggleJamoMode())
A_TrayMenu.Add("清除缓存 (Esc)", (*) => ClearRoman())
A_TrayMenu.Add()
A_TrayMenu.Add("退出", (*) => ExitApp())
A_TrayMenu.Default := "启用/关闭 (F10)"
UpdateTray()

F8::ToggleJamoMode()
F9::ToggleMode()
F10::ToggleBridge()
~LButton::ClearRoman()
~RButton::ClearRoman()
#HotIf BridgeOn || JamoMode
Esc::CancelIfBuffer()
#HotIf

ModeName() {
    global Mode
    return Mode = "MOE1959" ? "1959 文教部式（正字转换）" : "2000 文观部式（RR 字符近似）"
}

UpdateTray() {
    global BridgeOn, JamoMode
    A_IconTip := "Roman2Hangul: " (JamoMode ? "独立字母" : (BridgeOn ? "开启" : "关闭")) " - " (JamoMode ? "1959" : ModeName())
}

ToggleMode() {
    global Mode, JamoMode
    if JamoMode
        return ; F8 must restore exactly the previous original mode
    if !CommitRoman()
        return
    Mode := Mode = "MOE1959" ? "RR2000" : "MOE1959"
    UpdateTray()
    InputFocusTip("转换规则: " ModeName() "`n有歧义时使用连字符 - 显式分音节")
    SetTimer(() => ToolTip(), -2200)
}

ToggleBridge() {
    global BridgeOn, Interceptor, JamoMode
    if JamoMode
        return ; do not change the underlying ON/OFF state during F8 override
    if BridgeOn {
        if !CommitRoman()
            return
        Interceptor.Stop()
        BridgeOn := false
        InputFocusTip("转换：关闭")
    } else {
        ClearRoman()
        Interceptor.Start()
        BridgeOn := true
        InputFocusTip("转换：开启。" ModeName() "`n请将韩语 IME 切换到 한 模式")
    }
    UpdateTray()
    SetTimer(() => ToolTip(), -1800)
}

CancelIfBuffer() {
    global RomanBuffer, JamoMode, JamoPending
    if JamoMode && JamoPending != ""
        ClearRoman()
    else if RomanBuffer != ""
        ClearRoman()
    else
        SendEvent("{Esc}")
}

ClearRoman() {
    global RomanBuffer, BufferWindow, JamoPending
    RomanBuffer := ""
    JamoPending := ""
    BufferWindow := 0
    ToolTip()
}

ShowPending() {
    global RomanBuffer
    if RomanBuffer = "" {
        ToolTip()
        return
    }
    try {
        preview := RomanToHangul(RomanBuffer)
        InputFocusTip(ModeName() "`n" RomanBuffer " → " preview "`n空格提交 | 回车不带空格提交 | - 分音节")
    } catch {
        InputFocusTip(ModeName() "`n罗马字: " RomanBuffer "`n尚不能解析，请继续输入或退格")
    }
}

ObserveDown(ih, vk, sc) {
    global BridgeOn, RomanBuffer, BufferWindow, PhysicalLetters, JamoMode, JamoPending
    if !BridgeOn && !JamoMode
        return
    if IsShortcutModifier(vk) {
        if JamoMode
            CommitJamo()
        else
            CommitRoman()
        ih.KeyOpt(PhysicalLetters, "V")
        return
    }
    if HasShortcutModifier()
        return
    if JamoMode {
        if (vk >= 0x41 && vk <= 0x5A) {
            active := WinGetID("A")
            if (BufferWindow && BufferWindow != active)
                ClearRoman()
            if !BufferWindow
                BufferWindow := active
            FeedJamo(StrLower(Chr(vk)))
            return
        }
        switch vk {
            case 0x08:
                if JamoPending != "" {
                    JamoPending := SubStr(JamoPending, 1, StrLen(JamoPending)-1)
                    ShowJamoPending()
                } else
                    SendEvent("{vk08}")
            case 0x20:
                if CommitJamo()
                    SendEvent("{vk20}")
            case 0x0D:
                CommitJamo() ; Enter submits only; do not forward Enter to the target
            case 0x09:
                if CommitJamo()
                    SendEvent("{vk09}")
            case 0xBD, 0xDE:
                if JamoPending != "" {
                    CommitJamo() ; silent token boundary: o-e -> ㅗㅔ
                } else
                    SendVK(vk)
            case 0xBE, 0xBC, 0xBF, 0xBA:
                if CommitJamo()
                    SendVK(vk)
            default:
                if (vk >= 0x30 && vk <= 0x39) {
                    if CommitJamo()
                        SendVK(vk)
                } else if (JamoPending != "" && IsNavigation(vk)) {
                    CommitJamo()
                }
        }
        return
    }
    if (vk >= 0x41 && vk <= 0x5A) {
        active := WinGetID("A")
        if (BufferWindow && BufferWindow != active)
            ClearRoman()
        if !BufferWindow
            BufferWindow := active
        RomanBuffer .= StrLower(Chr(vk))
        ShowPending()
        return
    }
    switch vk {
        case 0x08:
            if RomanBuffer != "" {
                RomanBuffer := SubStr(RomanBuffer, 1, StrLen(RomanBuffer) - 1)
                ShowPending()
            } else
                SendEvent("{vk08}")
        case 0x20:
            if CommitRoman()
                SendEvent("{vk20}")
        case 0x0D:
            CommitRoman() ; Enter submits only; do not forward Enter to the target
        case 0x09:
            if CommitRoman()
                SendEvent("{vk09}")
        case 0xBD, 0xDE:
            if RomanBuffer != "" {
                if SubStr(RomanBuffer, -1) != "-"
                    RomanBuffer .= "-"
                ShowPending()
            } else
                SendVK(vk)
        case 0xBE, 0xBC, 0xBF, 0xBA:
            if CommitRoman()
                SendVK(vk)
        default:
            if (vk >= 0x30 && vk <= 0x39) {
                if CommitRoman()
                    SendVK(vk)
            } else if (RomanBuffer != "" && IsNavigation(vk)) {
                CommitRoman()
            }
    }
}

ObserveUp(ih, vk, sc) {
    global BridgeOn, JamoMode, PhysicalLetters
    if ((BridgeOn || JamoMode) && IsShortcutModifier(vk) && !HasShortcutModifier())
        ih.KeyOpt(PhysicalLetters, "S")
}

IsShortcutModifier(vk) {
    return vk = 0x11 || vk = 0x12 || vk = 0x5B || vk = 0x5C
        || vk = 0xA2 || vk = 0xA3 || vk = 0xA4 || vk = 0xA5
}

HasShortcutModifier() {
    return GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
}

IsNavigation(vk) {
    return (vk >= 0x21 && vk <= 0x28) || vk = 0x2D || vk = 0x2E
}

SendVK(vk) {
    SendEvent((GetKeyState("Shift", "P") ? "+" : "") "{vk" Format("{:02X}", vk) "}")
}

; Returns true only after safe submission; an invalid buffer must not be lost.
CommitRoman() {
    global RomanBuffer, BufferWindow, JamoMode
    if JamoMode
        return CommitJamo()
    if RomanBuffer = ""
        return true
    text := RomanBuffer
    try {
        parsed := ParseRoman(text)
    } catch as err {
        SoundBeep(800, 130)
        InputFocusTip("不能转换：" text "`n" err.Message "`n用 - 指定音节边界，退格修改，或 Esc 清除")
        return false
    }
    RomanBuffer := ""
    BufferWindow := 0
    ToolTip()
    for syllable in parsed
        SendSyllable(syllable)
    return true
}

RomanToHangul(text) {
    syllables := ParseRoman(text)
    out := ""
    for syllable in syllables
        out .= syllable.letter
    return out
}

ParseRoman(text) {
    global Mode
    pieces := StrSplit(StrLower(text), "-")
    all := []
    for i, piece in pieces {
        if piece = "" {
            if (i = pieces.Length && pieces.Length > 1)
                continue
            throw Error("有空音节；只允许在两个音节之间放 -")
        }
        memo := Map()
        result := SolveRoman(piece, 1, Mode, memo)
        if !result.ok
            throw Error("不支持或无法分音节：" piece)
        for s in result.syllables
            all.Push(s)
    }
    return all
}

SolveRoman(text, pos, mode, memo) {
    if pos > StrLen(text)
        return {ok:true, score:0, syllables:[]}
    if memo.Has(pos)
        return memo[pos]
    best := {ok:false, score:1e9, syllables:[]}
    for onset in OnsetTokens(mode) {
        if !TokenAt(text, pos, onset)
            continue
        vowelStart := pos + StrLen(onset)
        for vowel in VowelTokens(mode) {
            if !TokenAt(text, vowelStart, vowel)
                continue
            codaStart := vowelStart + StrLen(vowel)
            for coda in CodaTokens(mode) {
                if !TokenAt(text, codaStart, coda)
                    continue
                nextPos := codaStart + StrLen(coda)
                tail := SolveRoman(text, nextPos, mode, memo)
                if !tail.ok
                    continue
                cost := 1 + tail.score + ((onset = "" && pos > 1) ? 6 : 0)
                if coda != ""
                    cost += 0.15
                if (!best.ok || cost < best.score) {
                    syllable := MakeSyllable(onset, vowel, coda, mode)
                    newSyllables := [syllable]
                    for tailSyllable in tail.syllables
                        newSyllables.Push(tailSyllable)
                    best := {ok:true, score:cost, syllables:newSyllables}
                }
            }
        }
    }
    memo[pos] := best
    return best
}

TokenAt(text, pos, token) {
    return token = "" || SubStr(text, pos, StrLen(token)) = token
}

OnsetTokens(mode) {
    if mode = "MOE1959"
        return ["gg", "dd", "bb", "ss", "jj", "ch", "g", "n", "d", "r", "m", "b", "s", "j", "k", "t", "p", "h", ""]
    return ["kk", "tt", "pp", "ss", "jj", "ch", "g", "n", "d", "r", "m", "b", "s", "j", "k", "t", "p", "h", ""]
}

VowelTokens(mode) {
    if mode = "MOE1959"
        return ["yae", "yeo", "eui", "wae", "eo", "eu", "ae", "ya", "yo", "yu", "ye", "oe", "wi", "wa", "wo", "we", "a", "o", "u", "i", "e"]
    return ["yae", "yeo", "wae", "eo", "eu", "ae", "ya", "yo", "yu", "ye", "oe", "wi", "ui", "wa", "wo", "we", "a", "o", "u", "i", "e"]
}

CodaTokens(mode) {
    if mode = "MOE1959"
        return ["ng", "gg", "gs", "nj", "nh", "lg", "lm", "lb", "ls", "lt", "lp", "lh", "bs", "ss", "ch", "g", "n", "d", "l", "m", "b", "s", "j", "k", "t", "p", "h", ""]
    return ["ng", "ss", "kk", "n", "l", "m", "k", "t", "p", ""]
}

MakeSyllable(onset, vowel, coda, mode) {
    if mode = "MOE1959" {
        initials := Map("",11,"g",0,"gg",1,"n",2,"d",3,"dd",4,"r",5,"m",6,"b",7,"bb",8,"s",9,"ss",10,"j",12,"jj",13,"ch",14,"k",15,"t",16,"p",17,"h",18)
        finals := Map("",0,"g",1,"gg",2,"gs",3,"n",4,"nj",5,"nh",6,"d",7,"l",8,"lg",9,"lm",10,"lb",11,"ls",12,"lt",13,"lp",14,"lh",15,"m",16,"b",17,"bs",18,"s",19,"ss",20,"ng",21,"j",22,"ch",23,"k",24,"t",25,"p",26,"h",27)
    } else {
        initials := Map("",11,"g",0,"kk",1,"n",2,"d",3,"tt",4,"r",5,"m",6,"b",7,"pp",8,"s",9,"ss",10,"j",12,"jj",13,"ch",14,"k",15,"t",16,"p",17,"h",18)
        finals := Map("",0,"n",4,"l",8,"m",16,"k",1,"t",7,"p",17,"ng",21,"ss",20,"kk",2)
    }
    vowels := Map("a",0,"ae",1,"ya",2,"yae",3,"eo",4,"e",5,"yeo",6,"ye",7,"o",8,"wa",9,"wae",10,"oe",11,"yo",12,"u",13,"wo",14,"we",15,"wi",16,"yu",17,"eu",18,"i",20)
    vowels[mode = "MOE1959" ? "eui" : "ui"] := 19
    if !initials.Has(onset) || !vowels.Has(vowel) || !finals.Has(coda)
        throw Error("无法匹配罗马字音节")
    cho := initials[onset]
    jung := vowels[vowel]
    jong := finals[coda]
    letter := Chr(0xAC00 + (cho * 21 + jung) * 28 + jong)
    return {cho:cho, jung:jung, jong:jong, letter:letter}
}

SendSyllable(syllable) {
    initials := ["r","R","s","e","E","f","a","q","Q","t","T","d","w","W","c","z","x","v","g"]
    vowels := ["k","o","i","O","j","p","u","P","h","hk","ho","hl","y","n","nj","np","nl","b","m","ml","l"]
    finals := ["","r","R","rt","s","sw","sg","e","f","fr","fa","fq","ft","fx","fv","fg","a","q","qt","t","T","d","w","c","z","x","v","g"]
    SendKeys(initials[syllable.cho+1])
    SendKeys(vowels[syllable.jung+1])
    if syllable.jong != 0
        SendKeys(finals[syllable.jong+1])
}

SendKeys(spec) {
    for letter in StrSplit(spec) {
        vk := Ord(StrUpper(letter))
        key := "{vk" Format("{:02X}", vk) "}"
        SendEvent(letter !== StrLower(letter) ? "+" key : key)
    }
}

; Standalone letter mode temporarily overrides the conversion state.
ToggleJamoMode() {
    global JamoMode, BridgeOn, Interceptor, JamoPending
    if JamoMode {
        if !CommitJamo()
            return
        JamoMode := false
        ClearRoman()
        if !BridgeOn
            Interceptor.Stop()
        UpdateTray()
        InputFocusTip("已恢复：" (BridgeOn ? ModeName() : "转换关闭"))
    } else {
        if BridgeOn && !CommitRoman()
            return
        ClearRoman()
        if !BridgeOn
            Interceptor.Start()
        JamoMode := true
        UpdateTray()
        InputFocusTip("F8 单独字母：1959 文教部式（不组音节）")
    }
    SetTimer(() => ToolTip(), -1500)
}

; Compatibility jamo U+3131..U+3163 are stand-alone display characters.
; We inject the finished character, not a sequence of Korean IME keystrokes.
JamoTable() {
    static mapping := Map(
        "g", "ㄱ", "gg", "ㄲ", "gs", "ㄳ", "n", "ㄴ", "nj", "ㄵ", "nh", "ㄶ",
        "d", "ㄷ", "dd", "ㄸ", "r", "ㄹ", "l", "ㄹ", "lg", "ㄺ", "lm", "ㄻ",
        "lb", "ㄼ", "ls", "ㄽ", "lt", "ㄾ", "lp", "ㄿ", "lh", "ㅀ",
        "m", "ㅁ", "b", "ㅂ", "bb", "ㅃ", "bs", "ㅄ", "s", "ㅅ", "ss", "ㅆ",
        "ng", "ㅇ", "j", "ㅈ", "jj", "ㅉ", "ch", "ㅊ", "k", "ㅋ", "t", "ㅌ", "p", "ㅍ", "h", "ㅎ",
        "a", "ㅏ", "ae", "ㅐ", "ya", "ㅑ", "yae", "ㅒ", "eo", "ㅓ", "e", "ㅔ",
        "yeo", "ㅕ", "ye", "ㅖ", "o", "ㅗ", "wa", "ㅘ", "wae", "ㅙ", "oe", "ㅚ",
        "yo", "ㅛ", "u", "ㅜ", "wo", "ㅝ", "we", "ㅞ", "wi", "ㅟ", "yu", "ㅠ",
        "eu", "ㅡ", "eui", "ㅢ", "i", "ㅣ")
    return mapping
}

FeedJamo(letter) {
    global JamoPending
    ; A second identical consonant completes a 1959 tense-jamo token.
    ; Commit it atomically instead of splitting into two separate jamo.
    if (JamoPending = letter && InStr("|g|d|b|j|s|", "|" letter "|")) {
        pair := letter letter
        mapping := JamoTable()
        if mapping.Has(pair) {
            SendText(mapping[pair])
            JamoPending := ""
            ShowJamoPending()
            return
        }
    }
    JamoPending .= letter
    DrainJamo(false)
    ShowJamoPending()
}

; Keep a prefix only while it can still grow into a longer 1959 token.
; A hyphen/apostrophe, Enter, space, or F8 flushes an ambiguous final token.
DrainJamo(force) {
    global JamoPending
    mapping := JamoTable()
    while JamoPending != "" {
        canExtend := false
        best := ""
        bestValue := ""
        for token, value in mapping {
            if (StrLen(token) > StrLen(JamoPending) && SubStr(token, 1, StrLen(JamoPending)) = JamoPending)
                canExtend := true
            if (StrLen(token) > StrLen(best) && SubStr(JamoPending, 1, StrLen(token)) = token) {
                best := token
                bestValue := value
            }
        }
        if !force && canExtend
            break
        if best = ""
            return false
        SendText(bestValue)
        JamoPending := SubStr(JamoPending, StrLen(best) + 1)
    }
    return true
}

CommitJamo() {
    if !DrainJamo(true) {
        SoundBeep(800, 130)
        ShowJamoPending()
        return false
    }
    ShowJamoPending()
    return true
}

ShowJamoPending() {
    global JamoPending
    if JamoPending = ""
        ToolTip()
    else
        InputFocusTip("独立字母（1959）：" JamoPending "`n回车确认当前字母；- 隔开相邻字母")
}

; Tooltip placement for input focus (v0.2.5).
; Anchor horizontally at the text caret. Keep the ENTIRE tooltip below the
; focused edit box, not 22px below the caret's top inside the box.
; UI Automation makes Chrome/Edge edit-field bounds visible when Win32 focus
; reports only a full-window renderer. The mouse is never consulted.
InputFocusTip(message) {
    CoordMode("Caret", "Screen")
    CoordMode("ToolTip", "Screen")

    caret := 0
    field := 0
    ; Modern browsers often expose the focused edit via UI Automation,
    ; even when Windows' legacy caret API fails. Calls are best-effort only.
    try {
        info := FocusGeometryUIA()
        field := info.field
        caret := info.caret
    } catch {
        ; UI Automation unavailable in this editor; use Win32 instead.
    }

    if CaretGetPos(&caretX, &caretY) && caretX > 0 && caretY > 0 {
        ; Use native caret when it lies within the actual focused edit.
        if !IsObject(field) || PointInField(caretX, caretY, field)
            caret := {x:caretX, y:caretY, h:20}
    }

    if !IsObject(field) {
        ; Win32 fallback only when the focused control is a credible edit box.
        ; Chrome's renderer HWND is roughly as large as the entire window:
        ; never mistake its bottom edge for the input field's bottom edge.
        try {
            field := FocusGeometryWin32()
        } catch {
            ; The editor does not expose a normal focused control.
        }
    }

    x := 0
    y := 0
    if IsObject(caret) {
        x := caret.x
        y := caret.y + Max(caret.h, 18) + 8
    }
    if IsObject(field) {
        if !IsObject(caret)
            x := field.l + 8
        ; Essential: *outside* the input field, below its lower edge.
        y := Max(y, field.b + 8)
    }
    if !x || !y {
        ; Last resort: under the active window's client region, NEVER mouse.
        try {
            WinGetClientPos(&wx, &wy, &ww, &wh, "A")
            x := wx + 24
            y := wy + 40
        } catch {
            x := A_ScreenWidth // 2
            y := 48
        }
    }

    ; Render once to get the actual tooltip size (including CJK/wrapping).
    ToolTip(message, x, y)
    tw := 290, th := 80
    try {
        tipWindows := WinGetList("ahk_class tooltips_class32 ahk_pid " DllCall("GetCurrentProcessId", "uint"))
        for tipHwnd in tipWindows {
            WinGetPos(,, &realWidth, &realHeight, "ahk_id " tipHwnd)
            if realWidth > 0 && realHeight > 0 {
                tw := realWidth, th := realHeight
                break
            }
        }
    } catch {
        ; The tooltip may not yet have a visible window; estimate size.
    }

    ; Use the caret/control position when selecting monitor, not a tooltip
    ; location which may already be below the bottom work-area boundary.
    monitorY := IsObject(field) ? Max(field.t, field.b - 1) : (IsObject(caret) ? caret.y : y)
    GetAnchorWorkArea(x, monitorY, &ml, &mt, &mr, &mb)
    x := Max(ml + 4, Min(x, mr - tw - 4))
    if y + th > mb - 4 {
        ; When there is no room below (e.g. near the taskbar), show above
        ; the input field instead of overlapping the editor itself.
        topOfField := IsObject(field) ? field.t : (IsObject(caret) ? caret.y : y)
        yAbove := topOfField - th - 8
        if yAbove >= mt + 4
            y := yAbove
        else
            y := Max(mt + 4, mb - th - 4)
    }
    ToolTip(message, x, y)
}

PointInField(x, y, box) {
    return x >= box.l - 8 && x <= box.r + 8
        && y >= box.t - 8 && y <= box.b + 8
}

GetAnchorWorkArea(x, y, &l, &t, &r, &b) {
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &left, &top, &right, &bottom)
        if x >= left && x < right && y >= top && y < bottom {
            l := left, t := top, r := right, b := bottom
            return
        }
    }
    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
}

FocusGeometryWin32() {
    win := WinGetID("A")
    ws := "ahk_id " win
    focused := ControlGetFocus(ws)
    if focused = ""
        return 0
    ControlGetPos(&cx, &cy, &cw, &ch, focused, ws)
    WinGetClientPos(&wx, &wy, &ww, &wh, ws)
    if cw < 12 || ch < 16 || cw > ww * 0.94 || ch > wh * 0.70
        return 0
    return {l:wx+cx, t:wy+cy, r:wx+cx+cw, b:wy+cy+ch}
}

; COM calls here use only the built-in Windows UIAutomationClient interface:
; IUIAutomation::GetFocusedElement (vtable 8)
; IUIAutomationElement::get_CurrentBoundingRectangle (43)
; IUIAutomationElement::GetCurrentPattern (16), TextPattern2=10024
; IUIAutomationTextPattern2::GetCaretRange (10)
; IUIAutomationTextRange::GetBoundingRectangles (10).
; No external AHK library, clipboard access, or new hotkeys.
FocusGeometryUIA() {
    static automation := ComObject("{e22ad333-b25f-460c-83d0-0581107395c9}",
                                   "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    el := 0, pattern := 0, range := 0, rectangles := 0, accessed := false
    result := {field:0, caret:0}
    try {
        ComCall(8, automation, "ptr*", &el)
        if !el
            return result
        rect := Buffer(16, 0)
        ComCall(43, el, "ptr", rect)
        box := {l:NumGet(rect,0,"int"), t:NumGet(rect,4,"int"),
                r:NumGet(rect,8,"int"), b:NumGet(rect,12,"int")}
        ; Avoid bogus / entire-screen UIA elements.
        if box.r-box.l >= 12 && box.b-box.t >= 16
                && box.r-box.l < A_ScreenWidth*0.96
                && box.b-box.t < A_ScreenHeight*0.78
            result.field := box

        ; TextPattern2 can expose the *real* caret inside Chromium editors.
        try {
            ComCall(16, el, "int", 10024, "ptr*", &pattern)
            if pattern {
                active := 0
                ComCall(10, pattern, "int*", &active, "ptr*", &range)
                if active && range {
                    ComCall(10, range, "ptr*", &rectangles)
                    if rectangles {
                        lo := 0, hi := -1
                        DllCall("oleaut32\SafeArrayGetLBound", "ptr", rectangles, "uint", 1, "int*", &lo, "int")
                        DllCall("oleaut32\SafeArrayGetUBound", "ptr", rectangles, "uint", 1, "int*", &hi, "int")
                        if hi - lo + 1 >= 4 {
                            data := 0
                            if DllCall("oleaut32\SafeArrayAccessData", "ptr", rectangles, "ptr*", &data, "int") = 0 {
                                accessed := true
                                rx := NumGet(data, 0, "double")
                                ry := NumGet(data, 8, "double")
                                rh := NumGet(data, 24, "double")
                                if rx > 0 && ry > 0 && rh >= 0
                                    result.caret := {x:Round(rx), y:Round(ry), h:Max(1, Round(rh))}
                            }
                        }
                    }
                }
            }
        } catch {
            ; TextPattern2 unsupported; focused field bounds remain usable.
        }
    } finally {
        if accessed
            DllCall("oleaut32\SafeArrayUnaccessData", "ptr", rectangles)
        if rectangles
            DllCall("oleaut32\SafeArrayDestroy", "ptr", rectangles)
        if range
            ObjRelease(range)
        if pattern
            ObjRelease(pattern)
        if el
            ObjRelease(el)
    }
    return result
}
