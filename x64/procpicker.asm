; ==============================================================================
; Vault Guard - Process Picker Dialog
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Shows a modal dialog listing all running processes so the user can
;          pick one to add to the trusted (allowed) apps list.
;
; Exported:
;   ShowProcPicker(rcx=hwndOwner)  →  eax=count added (0 = cancelled/nothing)
; ==============================================================================

option casemap:none

include consts.inc
include globals.inc

EXTRN CreateWindowExW           :PROC
EXTRN SendMessageW              :PROC
EXTRN DialogBoxIndirectParamW   :PROC
EXTRN EndDialog                 :PROC
EXTRN GetDlgItem                :PROC
EXTRN DwmSetWindowAttribute     :PROC
EXTRN DwmGetWindowAttribute     :PROC
EXTRN FillRect                  :PROC
EXTRN SetBkMode                 :PROC
EXTRN SetBkColor                :PROC
EXTRN SetTextColor              :PROC
EXTRN _SetLvColors              :PROC
EXTRN GetWindowRect             :PROC
EXTRN GetClientRect             :PROC
EXTRN SetWindowPos              :PROC
EXTRN CreateToolhelp32Snapshot  :PROC
EXTRN Process32FirstW           :PROC
EXTRN Process32NextW            :PROC
EXTRN CloseHandle               :PROC

EXTRN _LvAddColumn              :PROC   ; listview.asm

EXTRN wcs_ascii_lower_inplace   :PROC
EXTRN EnsureDriverReady         :PROC
EXTRN CloseDevice               :PROC
EXTRN IoctlAddTrusted           :PROC
EXTRN ConfigSaveTrusted         :PROC
EXTRN ConfigTrustedCanAdd       :PROC
EXTRN ConfigLoad                :PROC

; ==============================================================================
; CONSTANT STRINGS
; ==============================================================================
.const

pp_str_col_proc dw 'P','r','o','c','e','s','s',0

; ==============================================================================
; DIALOG TEMPLATE
; Header (68 bytes) + 3 items = 198 bytes total.
; Layout (DLU): 220×180 — SysListView32 + Select + Cancel buttons.
; ==============================================================================
    align 4
pp_dlg_tmpl label byte
    ; DLGTEMPLATE header: style + exStyle + cdit + x,y,cx,cy + menu + class + title
    dd  080C80880h          ; WS_POPUP|WS_CAPTION|WS_SYSMENU|DS_MODALFRAME|DS_CENTER
    dd  0
    dw  3                   ; cdit = 3 items
    dw  0, 0, 220, 205      ; x=0 y=0 cx=220 cy=205 (DLU)
    dw  0, 0                ; menu=none, wndClass=none
    ; title "Select running process\0" = 23 WCHARs = 46 bytes (starts at offset 22)
    dw  'S','e','l','e','c','t',' ','r','u','n','n','i','n','g',' '
    dw  'p','r','o','c','e','s','s',0
    ; end of header at offset 22+46 = 68, DWORD aligned (68 % 4 = 0) ✓

    ; Item 0: SysListView32 at offset 68 (total body = 50 bytes → end 118 → pad 2 → 120)
    dd  050000001h          ; WS_CHILD|WS_VISIBLE|LVS_REPORT
    dd  00000200h           ; WS_EX_CLIENTEDGE
    dw  6, 6, 208, 175      ; x=6, y=6, cx=208, cy=175
    dw  IDC_LV_PROCPICK     ; id=219
    ; wndClass "SysListView32\0" = 14 WCHARs = 28 bytes
    dw  'S','y','s','L','i','s','t','V','i','e','w','3','2',0
    dw  0                   ; text = "" (empty string)
    dw  0                   ; extraCount = 0
    dw  0                   ; 2-byte pad to DWORD align (118→120)

    ; Item 1: Select button at offset 120 (38 bytes → end 158 → pad 2 → 160)
    dd  050010001h          ; WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_DEFPUSHBUTTON
    dd  0
    dw  45, 186, 60, 14     ; x=45, y=186, cx=60, cy=14
    dw  IDOK                ; id=1
    dw  0FFFFh, 0080h       ; BUTTON atom
    dw  'S','e','l','e','c','t',0
    dw  0                   ; extraCount = 0
    dw  0                   ; 2-byte pad (158→160)

    ; Item 2: Cancel button at offset 160 (38 bytes → end 198)
    dd  050010000h          ; WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_PUSHBUTTON
    dd  0
    dw  115, 186, 60, 14    ; x=115, y=186, cx=60, cy=14
    dw  IDCANCEL            ; id=2
    dw  0FFFFh, 0080h       ; BUTTON atom
    dw  'C','a','n','c','e','l',0
    dw  0                   ; extraCount = 0

; ==============================================================================
; DATA
; ==============================================================================
.data
    align 8

pp_lv_item          db LVITEMW_SIZE dup(0)  ; scratch LVITEMW for insertions

.data?
    align 8
    pp_hwnd_lv          dq ?                ; hwnd of the LV inside the dialog
    pp_entry            db PROCESSENTRY32W_SIZE dup(?) ; Toolhelp32 scratch
    pp_name_buf         dw (MAX_PATH + 4) dup(?)

; ==============================================================================
; CODE
; ==============================================================================
.code

PUBLIC ShowProcPicker

; ==============================================================================
; _ProcPickDlgProc  rcx=hwnd  rdx=msg  r8=wParam  r9=lParam  →  rax=TRUE/FALSE
; Stack: 5 pushes (40) + sub 40h (64) = 104; entry rsp%16=8; 8-104%16=8-8=0 ✓
; ==============================================================================
_ProcPickDlgProc proc
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 60h

    mov     rbx, rcx            ; hwnd
    mov     esi, edx            ; msg
    mov     rdi, r8             ; wParam

    cmp     esi, WM_INITDIALOG
    je      @pp_init
    cmp     esi, WM_COMMAND
    je      @pp_cmd
    cmp     esi, WM_NOTIFY
    je      @pp_notify
    cmp     esi, WM_ERASEBKGND
    je      @pp_erase
    cmp     esi, WM_CTLCOLORSTATIC
    je      @pp_ctlcolor
    cmp     esi, WM_CTLCOLORBTN
    je      @pp_ctlcolor
    xor     eax, eax
    jmp     @pp_ret

; ── WM_INITDIALOG ─────────────────────────────────────────────────────────────
@pp_init:
    ; Match height to owner (main window)
    mov     rcx, g_hwndMain
    test    rcx, rcx
    jz      @pp_skip_resize
    lea     rdx, [rsp+20h]      ; &RECT
    call    GetWindowRect
    
    mov     eax, dword ptr [rsp+20h+12] ; bottom
    sub     eax, dword ptr [rsp+20h+4]  ; top
    mov     r12d, eax                   ; target height in pixels

    ; Visible bounds of main (DWM extended frame excludes invisible shadow border)
    mov     r9d, 16
    lea     r8, [rsp+20h]
    mov     edx, 9                      ; DWMWA_EXTENDED_FRAME_BOUNDS
    mov     rcx, g_hwndMain
    call    DwmGetWindowAttribute
    mov     eax, dword ptr [rsp+20h+8]  ; main visible right
    mov     dword ptr [rsp+48h], eax
    mov     eax, dword ptr [rsp+20h+4]  ; main visible top
    mov     dword ptr [rsp+4Ch], eax

    ; Dialog GetWindowRect: width + save .left for invisible-border calc
    mov     rcx, rbx
    lea     rdx, [rsp+20h]
    call    GetWindowRect
    mov     r14d, dword ptr [rsp+20h]   ; save dialog GetWindowRect.left
    mov     r13d, dword ptr [rsp+20h+8] ; right
    sub     r13d, r14d                  ; r13d = dialog width

    ; Dialog visible left (DWM) — to compute invisible left border
    mov     r9d, 16
    lea     r8, [rsp+20h]
    mov     edx, 9                      ; DWMWA_EXTENDED_FRAME_BOUNDS
    mov     rcx, rbx
    call    DwmGetWindowAttribute
    ; X = main_visible_right - (dialog_visible_left - dialog_GetWindowRect_left)
    mov     eax, dword ptr [rsp+20h]    ; dialog visible left
    sub     eax, r14d                   ; eax = invisible left border width
    mov     r14d, dword ptr [rsp+48h]   ; main visible right
    sub     r14d, eax                   ; X = main.right - invisible_border → exact touch
    mov     dword ptr [rsp+48h], r14d   ; save final X

    ; Resize to match main window height
    mov     dword ptr [rsp+30h], 6      ; SWP_NOMOVE | SWP_NOZORDER
    mov     dword ptr [rsp+28h], r12d   ; height
    mov     dword ptr [rsp+20h], r13d   ; width
    xor     r9d, r9d
    xor     r8d, r8d
    xor     edx, edx
    mov     rcx, rbx
    call    SetWindowPos

    ; Left edge of dialog touches right edge of main window exactly
    mov     r8d, dword ptr [rsp+48h]    ; X (corrected for invisible border)
    mov     r9d, dword ptr [rsp+4Ch]    ; Y = main visible top
    mov     dword ptr [rsp+30h], 5      ; SWP_NOSIZE | SWP_NOZORDER
    xor     edx, edx
    mov     rcx, rbx
    call    SetWindowPos

    ; ── Reposition children in pixels ───────────────────────────────────────
    lea     rdx, [rsp+20h]
    mov     rcx, rbx
    call    GetClientRect
    mov     r14d, dword ptr [rsp+20h+8] ; client width
    mov     r15d, dword ptr [rsp+20h+12]; client height

    ; ListView
    mov     edx, IDC_LV_PROCPICK
    mov     rcx, rbx
    call    GetDlgItem
    mov     pp_hwnd_lv, rax
    mov     rsi, rax

    mov     eax, r15d
    sub     eax, 55                     ; client height - space for buttons
    mov     dword ptr [rsp+28h], eax    ; height
    mov     eax, r14d
    sub     eax, 16                     ; width - margins
    mov     dword ptr [rsp+20h], eax    ; width
    mov     dword ptr [rsp+30h], 4      ; SWP_NOZORDER
    mov     r9d, 8                      ; y
    mov     r8d, 8                      ; x
    xor     edx, edx
    mov     rcx, rsi
    call    SetWindowPos

    ; Select button
    mov     edx, IDOK
    mov     rcx, rbx
    call    GetDlgItem
    mov     rsi, rax

    mov     dword ptr [rsp+30h], 4
    mov     dword ptr [rsp+28h], 28     ; button height
    mov     dword ptr [rsp+20h], 85     ; button width
    mov     eax, r15d
    sub     eax, 38                     ; bottom margin
    mov     r9d, eax
    mov     eax, r14d
    shr     eax, 1                      ; width / 2
    sub     eax, 90                     ; center offset
    mov     r8d, eax
    xor     edx, edx
    mov     rcx, rsi
    call    SetWindowPos

    ; Cancel button
    mov     edx, IDCANCEL
    mov     rcx, rbx
    call    GetDlgItem
    mov     rsi, rax

    mov     dword ptr [rsp+30h], 4
    mov     dword ptr [rsp+28h], 28
    mov     dword ptr [rsp+20h], 85
    mov     eax, r15d
    sub     eax, 38
    mov     r9d, eax
    mov     eax, r14d
    shr     eax, 1
    add     eax, 5                      ; gap
    mov     r8d, eax
    xor     edx, edx
    mov     rcx, rsi
    call    SetWindowPos

@pp_skip_resize:
    ; Dark title bar
    mov     r9d, 4
    lea     r8, g_isDarkMode
    mov     edx, DWMWA_USE_IMMERSIVE_DARK_MODE
    mov     rcx, rbx
    call    DwmSetWindowAttribute

    ; Store ListView hwnd for snapshot processing
    mov     edx, IDC_LV_PROCPICK
    mov     rcx, rbx
    call    GetDlgItem
    mov     pp_hwnd_lv, rax
    mov     r12, rax                            ; r12 = hwndLvProc

    ; Apply dark/light theme to ListView
    mov     edx, g_isDarkMode
    mov     rcx, r12
    call    _SetLvColors

    ; Extended styles: full-row select + double buffer
    mov     r9d, (LVS_EX_FULLROWSELECT + LVS_EX_DOUBLEBUFFER)
    mov     r8d, (LVS_EX_FULLROWSELECT + LVS_EX_DOUBLEBUFFER)
    mov     edx, LVM_SETEXTENDEDLISTVIEWSTYLE
    mov     rcx, r12
    call    SendMessageW

    ; Add "Process" column, full width
    mov     r9, offset pp_str_col_proc
    mov     eax, r14d
    sub     eax, 40                             ; client width minus scrollbar/margins
    mov     r8d, eax
    xor     edx, edx
    mov     rcx, r12
    call    _LvAddColumn

    ; Snapshot all running processes
    xor     edx, edx                    ; th32ProcessID = 0
    mov     ecx, TH32CS_SNAPPROCESS
    call    CreateToolhelp32Snapshot
    cmp     rax, INVALID_HANDLE_VALUE
    je      @pp_init_done
    mov     r13, rax                    ; r13 = snapshot handle

    ; Set required dwSize field
    lea     rcx, pp_entry
    mov     dword ptr [rcx + PE32W_dwSize], PROCESSENTRY32W_SIZE

    lea     rdx, pp_entry
    mov     rcx, r13
    call    Process32FirstW
    test    eax, eax
    jz      @pp_snapshot_close

    xor     r12d, r12d                  ; row index

@pp_enum_loop:
    ; Prepare LVITEMW for LVM_INSERTITEMW
    lea     rax, pp_lv_item
    mov     dword ptr [rax + LVITEMW_mask],       LVIF_TEXT
    mov     dword ptr [rax + LVITEMW_iItem],       r12d
    mov     dword ptr [rax + LVITEMW_iSubItem],    0
    mov     dword ptr [rax + LVITEMW_state],       0
    mov     dword ptr [rax + LVITEMW_stateMask],   0
    lea     rcx, pp_entry
    add     rcx, PE32W_szExeFile                ; ptr into szExeFile
    mov     qword ptr [rax + LVITEMW_pszText],  rcx
    mov     dword ptr [rax + LVITEMW_cchTextMax], 260
    mov     qword ptr [rax + LVITEMW_lParam],   0

    lea     r9, pp_lv_item
    xor     r8d, r8d
    mov     edx, LVM_INSERTITEMW
    mov     rcx, qword ptr [pp_hwnd_lv]
    call    SendMessageW

    inc     r12d

    lea     rdx, pp_entry
    mov     rcx, r13
    call    Process32NextW
    test    eax, eax
    jnz     @pp_enum_loop

@pp_snapshot_close:
    mov     rcx, r13
    call    CloseHandle

@pp_init_done:
    mov     eax, 1
    jmp     @pp_ret

; ── WM_COMMAND ────────────────────────────────────────────────────────────────
@pp_cmd:
    movzx   ecx, di                     ; low word of wParam = control ID
    cmp     ecx, IDOK
    je      @pp_do_select
    cmp     ecx, IDCANCEL
    je      @pp_cancel
    xor     eax, eax
    jmp     @pp_ret

@pp_do_select:
    call    EnsureDriverReady
    test    eax, eax
    jz      @pp_ok_nothing

    mov     r12, -1                             ; iItem = -1 (start sentinel)
    xor     r13d, r13d                          ; count of items added
    mov     r14, qword ptr [pp_hwnd_lv]

@pp_select_loop:
    mov     r9d, LVNI_SELECTED
    mov     r8, r12                             ; previous iItem
    mov     edx, LVM_GETNEXTITEM
    mov     rcx, r14
    call    SendMessageW
    cmp     rax, -1
    je      @pp_select_done
    mov     r12, rax                            ; iItem = found index

    ; Get item text into pp_name_buf
    lea     rax, pp_lv_item
    mov     dword ptr [rax + LVITEMW_mask],       LVIF_TEXT
    mov     dword ptr [rax + LVITEMW_iItem],       r12d
    mov     dword ptr [rax + LVITEMW_iSubItem],    0
    lea     rcx, pp_name_buf
    mov     qword ptr [rax + LVITEMW_pszText],  rcx
    mov     dword ptr [rax + LVITEMW_cchTextMax], MAX_PATH

    lea     r9, pp_lv_item
    mov     r8, r12
    mov     edx, LVM_GETITEMTEXTW
    mov     rcx, r14
    call    SendMessageW

    lea     rcx, pp_name_buf
    call    wcs_ascii_lower_inplace

    ; Stop (one message) once the driver list is full; earlier picks are kept
    lea     rcx, pp_name_buf
    mov     rdx, rbx                            ; owner = picker dialog
    call    ConfigTrustedCanAdd
    test    eax, eax
    jz      @pp_select_done

    lea     rcx, pp_name_buf
    call    IoctlAddTrusted
    test    eax, eax
    jz      @pp_select_next
    lea     rcx, pp_name_buf
    call    ConfigSaveTrusted

@pp_select_next:
    inc     r13d
    jmp     @pp_select_loop

@pp_select_done:
    call    CloseDevice
    call    ConfigLoad                 ; individual setters replace; restore full list
    test    r13d, r13d
    jz      @pp_ok_nothing

    mov     edx, r13d
    mov     rcx, rbx
    call    EndDialog
    mov     eax, 1
    jmp     @pp_ret

@pp_ok_nothing:
    mov     eax, 1
    jmp     @pp_ret

@pp_cancel:
    xor     edx, edx
    mov     rcx, rbx
    call    EndDialog
    mov     eax, 1
    jmp     @pp_ret

; ── WM_NOTIFY — double-click on LV acts as Select ─────────────────────────────
@pp_notify:
    mov     ecx, dword ptr [r9 + 16]    ; NMHDR.nCode
    cmp     ecx, NM_DBLCLK
    jne     @pp_notify_ret
    mov     edi, IDOK                   ; fake IDOK command
    jmp     @pp_do_select

@pp_notify_ret:
    xor     eax, eax
    jmp     @pp_ret

; ── WM_ERASEBKGND — fill dialog background with dark brush ────────────────────
@pp_erase:
    cmp     g_isDarkMode, 0
    je      @pp_erase_def
    lea     rdx, [rsp+20h]
    mov     rcx, rbx
    call    GetClientRect
    mov     r8, g_hBrushBg
    lea     rdx, [rsp+20h]
    mov     rcx, rdi                ; wParam = HDC
    call    FillRect
    mov     eax, 1
    jmp     @pp_ret
@pp_erase_def:
    xor     eax, eax
    jmp     @pp_ret

; ── WM_CTLCOLORSTATIC / WM_CTLCOLORBTN — dark text + bg for child controls ────
@pp_ctlcolor:
    cmp     g_isDarkMode, 0
    je      @pp_ctlcolor_def
    mov     edx, OPAQUE_VAL
    mov     rcx, rdi                ; wParam = HDC
    call    SetBkMode
    mov     edx, COLORREF_DARK_BG
    mov     rcx, rdi
    call    SetBkColor
    mov     edx, COLORREF_DARK_TEXT
    mov     rcx, rdi
    call    SetTextColor
    mov     rax, g_hBrushBg
    jmp     @pp_ret
@pp_ctlcolor_def:
    xor     eax, eax

@pp_ret:
    add     rsp, 60h
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
_ProcPickDlgProc endp

; ==============================================================================
; ShowProcPicker  rcx=hwndOwner  →  eax=count added (0 = cancelled/nothing)
; Stack: 2 pushes (16) + sub 28h (40) = 56; entry rsp%16=8; 8-56%16=8-8=0 ✓
; ==============================================================================
ShowProcPicker proc
    push    rbx
    push    rsi
    sub     rsp, 28h

    mov     rbx, rcx                    ; hwndOwner

    mov     qword ptr [rsp+20h], 0      ; lParam = 0
    lea     r9, _ProcPickDlgProc
    mov     r8, rbx
    lea     rdx, pp_dlg_tmpl
    mov     rcx, g_hInstance
    call    DialogBoxIndirectParamW
    ; eax = count passed to EndDialog, or 0 if cancelled

    add     rsp, 28h
    pop     rsi
    pop     rbx
    ret
ShowProcPicker endp

end
