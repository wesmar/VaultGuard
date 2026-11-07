; ==============================================================================
; Vault Guard - Window Scaffold
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Window class registration, creation, message loop dispatch.
;
; Exported:
;   MainWndProc(rcx=hwnd, rdx=msg, r8=wParam, r9=lParam)  → rax
;   CreateMainWindow()                                      → rax = hwnd or NULL
; ==============================================================================

option casemap:none

include consts.inc
include globals.inc

; ── Win32 ─────────────────────────────────────────────────────────────────────
EXTRN RegisterClassExW          :PROC
EXTRN CreateWindowExW           :PROC
EXTRN DefWindowProcW            :PROC
EXTRN ShowWindow                :PROC
EXTRN UpdateWindow              :PROC
EXTRN DestroyWindow             :PROC
EXTRN PostQuitMessage           :PROC
EXTRN LoadCursorW               :PROC
EXTRN LoadIconW                 :PROC
EXTRN KillTimer                 :PROC
EXTRN DeleteObject              :PROC
EXTRN GetClientRect             :PROC
EXTRN GetDpiForSystem            :PROC
EXTRN AdjustWindowRectExForDpi   :PROC
EXTRN FillRect                  :PROC
EXTRN SetBkMode                 :PROC
EXTRN SetBkColor                :PROC
EXTRN SetTextColor              :PROC
EXTRN InvalidateRect            :PROC
EXTRN GetKeyState               :PROC
EXTRN RegisterWindowMessageW    :PROC

; ── Sibling modules ───────────────────────────────────────────────────────────
EXTRN _ReadDarkMode             :PROC   ; theme.asm
EXTRN ApplyDarkMode             :PROC   ; theme.asm
EXTRN _ApplyThemeColors         :PROC   ; theme.asm
EXTRN _OnCreate                 :PROC   ; layout.asm
EXTRN _OnDropFiles              :PROC   ; drop.asm
EXTRN RefreshLists              :PROC   ; listview.asm
EXTRN UpdateStatusBar           :PROC   ; handlers.asm
EXTRN _OnCommand                :PROC   ; handlers.asm
EXTRN _OnNotify                 :PROC   ; handlers.asm
EXTRN _TrayAdd                  :PROC   ; tray.asm
EXTRN _TrayRemove               :PROC   ; tray.asm
EXTRN _OnTrayMsg                :PROC   ; tray.asm

; ==============================================================================
; CONSTANT STRINGS  (owned by this module)
; ==============================================================================
.const

str_wndclass        dw 'V','G','M','a','i','n','W','n','d',0
str_title           dw 'V','a','u','l','t','G','u','a','r','d',' ','v','1','.','0','4',0
str_taskbarcreated  dw 'T','a','s','k','b','a','r','C','r','e','a','t','e','d',0

; ==============================================================================
; MUTABLE DATA
; ==============================================================================
.data
    align 4
PUBLIC g_wmTaskbarCreated
    g_wmTaskbarCreated  dd 0    ; message ID from RegisterWindowMessageW("TaskbarCreated")

; ==============================================================================
; CODE
; ==============================================================================
.code

; ==============================================================================
; MainWndProc  rcx=hwnd  rdx=msg  r8=wParam  r9=lParam  →  rax=result
;
; Stack: entry rsp%16=8; push rbx,rsi,rdi,r12 (+32)→8; sub 38h (+56)→0 ✓
; ==============================================================================
PUBLIC MainWndProc
MainWndProc proc
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 38h

    mov     rbx, rcx                        ; hwnd → rbx
    mov     rsi, rdx                        ; msg  → rsi
    mov     rdi, r8                         ; wParam → rdi
    mov     r12, r9                         ; lParam → r12

    cmp     esi, WM_CREATE
    jne     @wnd_not_create
    mov     rcx, rbx                        ; hwnd
    call    _OnCreate                       ; build all child controls
    xor     eax, eax                        ; return 0 = accept creation
    jmp     @wnd_ret

@wnd_not_create:
    cmp     esi, WM_DESTROY
    jne     @wnd_not_destroy

    mov     rcx, rbx
    call    _TrayRemove                     ; remove tray icon if visible

    mov     edx, TIMER_STATUS_ID
    mov     rcx, rbx
    call    KillTimer                       ; stop periodic refresh

    mov     rcx, g_hFontMain
    call    DeleteObject                    ; free main font GDI object
    mov     rcx, g_hFontSmall
    call    DeleteObject                    ; free small font GDI object
    mov     rcx, g_hBrushBg
    call    DeleteObject                    ; free background brush

    xor     ecx, ecx
    call    PostQuitMessage                 ; nExitCode = 0 → breaks msg loop
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_destroy:
    cmp     esi, WM_CLOSE
    jne     @wnd_not_close
    mov     rcx, rbx
    call    DestroyWindow                   ; triggers WM_DESTROY chain
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_close:
    cmp     esi, WM_SIZE
    jne     @wnd_not_size
    cmp     edi, SIZE_MINIMIZED             ; wParam = 1 when minimized
    jne     @wnd_not_size
    mov     ecx, VK_SHIFT
    call    GetKeyState
    test    ax, 8000h                       ; high bit = key currently pressed
    jz      @wnd_not_size
    mov     rcx, rbx
    call    _TrayAdd                        ; Shift+Minimize → hide to tray
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_size:
    cmp     esi, WM_TRAY
    jne     @wnd_not_tray
    mov     rdx, r12                        ; lParam = mouse event
    mov     rcx, rbx
    call    _OnTrayMsg
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_tray:
    cmp     esi, WM_DROPFILES
    jne     @wnd_not_dropfiles
    mov     rdx, rbx                        ; hMainWnd (for drop target detection)
    mov     rcx, rdi                        ; wParam = HDROP handle
    call    _OnDropFiles                    ; resolves .lnk, routes by drop target
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_dropfiles:
    cmp     esi, WM_NOTIFY
    jne     @wnd_not_notify
    mov     rdx, r12                        ; lParam = NMHDR*
    mov     rcx, rbx
    call    _OnNotify                       ; handles LV column checkbox clicks
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_notify:
    cmp     esi, WM_COMMAND
    jne     @wnd_not_command
    mov     rdx, rdi                        ; wParam (low word = control ID)
    mov     rcx, rbx
    call    _OnCommand                      ; toggle / add / remove path / trusted
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_command:
    cmp     esi, WM_TIMER
    jne     @wnd_not_timer
    cmp     edi, TIMER_STATUS_ID            ; ignore any other timer id
    jne     @wnd_not_timer
    call    UpdateStatusBar                 ; poll IOCTL → update title / labels
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_timer:
    ; TaskbarCreated: Explorer restarted → re-add tray icon if we were in tray mode
    mov     eax, g_wmTaskbarCreated
    test    eax, eax
    jz      @wnd_not_taskbar
    cmp     esi, eax
    jne     @wnd_not_taskbar
    cmp     g_startMinimized, 0
    je      @wnd_not_taskbar
    mov     rcx, rbx
    call    _TrayAdd
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_taskbar:
    cmp     esi, WM_SETTINGCHANGE
    jne     @wnd_not_setting
    call    _ReadDarkMode                   ; re-read AppsUseLightTheme registry val
    mov     rcx, rbx
    call    ApplyDarkMode                   ; DWM Mica + dark title bar
    call    _ApplyThemeColors               ; brush + SetWindowTheme + LV colors
    mov     r8d, 1                          ; bErase = TRUE
    xor     edx, edx                        ; lpRect = NULL (entire client)
    mov     rcx, rbx
    call    InvalidateRect                  ; force WM_PAINT / WM_ERASEBKGND
    xor     eax, eax
    jmp     @wnd_ret

@wnd_not_setting:
    cmp     esi, WM_ERASEBKGND
    jne     @wnd_not_erase
    lea     rdx, [rsp+20h]                  ; &RECT (stack local)
    mov     rcx, rbx
    call    GetClientRect                   ; fill RECT with client dimensions

    mov     r8, g_hBrushBg                  ; our solid background brush
    lea     rdx, [rsp+20h]                  ; lprc
    mov     rcx, rdi                        ; wParam = HDC
    call    FillRect                        ; paint client area with theme bg

    mov     eax, 1                          ; return 1 = background was erased
    jmp     @wnd_ret

@wnd_not_erase:
    cmp     esi, WM_CTLCOLORSTATIC
    jne     @wnd_def

    cmp     g_isDarkMode, 0                 ; skip dark paint in light mode
    je      @wnd_def

    mov     edx, OPAQUE_VAL
    mov     rcx, rdi                        ; wParam = HDC
    call    SetBkMode                       ; opaque so bg color is used
    mov     edx, COLORREF_DARK_BG
    mov     rcx, rdi
    call    SetBkColor                      ; static bg = dark panel color
    mov     edx, COLORREF_DARK_TEXT
    mov     rcx, rdi
    call    SetTextColor                    ; static text = light foreground
    mov     rax, g_hBrushBg                 ; return brush to paint control bg
    jmp     @wnd_ret

@wnd_def:
    mov     r9, r12
    mov     r8, rdi
    mov     rdx, rsi
    mov     rcx, rbx
    call    DefWindowProcW

@wnd_ret:
    add     rsp, 38h
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
MainWndProc endp

; ==============================================================================
; CreateMainWindow  →  rax = hwnd or NULL
;
; Registers class, creates a fixed modern Mica window.
; Stack: entry rsp%16=8; push rbx,rsi (+16)→8; sub 98h (+152)→0 ✓
; WNDCLASSEXW at [rsp+20h] (80 bytes); DPI-scaling RECT at [rsp+78h] (16
; bytes) + dpi DWORD at [rsp+88h]/[rsp+8Ch], both free once WNDCLASSEXW's
; slot is done with (RegisterClassExW has already consumed it by the time
; either is touched). 98h (152) chosen instead of the tempting 90h (144)
; because 144 mod 16 = 0 but 152 mod 16 = 8 -- alignment must match the
; ORIGINAL 78h's residue (also 8 mod 16), not just be a round number, or
; every CALL after this sub lands on a misaligned rsp. Got this wrong on
; the first pass (used 90h) and it crashed inside USER32.dll (0xc0000005)
; from the resulting misaligned stack, not from bad arguments.
; ==============================================================================
PUBLIC CreateMainWindow
CreateMainWindow proc
    push    rbx
    push    rsi
    sub     rsp, 98h

    ; Register "TaskbarCreated" message so WndProc can re-add tray icon
    ; if Explorer restarts (e.g. crash, logon race condition at startup).
    lea     rcx, str_taskbarcreated
    call    RegisterWindowMessageW
    mov     g_wmTaskbarCreated, eax

    ; Zero WNDCLASSEXW at [rsp+20h]
    lea     r10, [rsp+20h]                  ; struct base on stack
    xor     eax, eax
    mov     ecx, WNDCLASSEXW_SIZE / 8       ; zero in 8-byte chunks
@cmw_zero:
    mov     qword ptr [r10], rax
    add     r10, 8
    dec     ecx
    jnz     @cmw_zero

    lea     r10, [rsp+20h]
    mov     dword ptr [r10 + 0],  WNDCLASSEXW_SIZE  ; cbSize
    mov     dword ptr [r10 + 4],  (CS_HREDRAW + CS_VREDRAW)  ; style: repaint on resize
    lea     rax, MainWndProc
    mov     qword ptr [r10 + 8],  rax              ; lpfnWndProc
    mov     rax, g_hInstance
    mov     qword ptr [r10 + 24], rax              ; hInstance
    mov     edx, IDI_ICON1                          ; try resource icon first
    mov     rcx, g_hInstance
    call    LoadIconW
    test    rax, rax
    jnz     @icon_ok
    mov     edx, 32516                              ; IDI_APPLICATION fallback
    xor     ecx, ecx
    call    LoadIconW
@icon_ok:
    lea     r10, [rsp+20h]
    mov     qword ptr [r10 + 32], rax              ; hIcon (large)
    mov     qword ptr [r10 + 72], rax              ; hIconSm (small taskbar)
    mov     edx, IDC_ARROW_ATOM                     ; standard arrow cursor
    xor     ecx, ecx
    call    LoadCursorW
    lea     r10, [rsp+20h]
    mov     qword ptr [r10 + 40], rax              ; hCursor
    lea     rax, str_wndclass
    mov     qword ptr [r10 + 64], rax              ; lpszClassName

    lea     rcx, [rsp+20h]
    call    RegisterClassExW
    test    ax, ax
    jz      @cmw_fail

    ; ── DPI-aware window size ────────────────────────────────────────────
    ; 700x550 was authored as the TOTAL window size at 96 DPI (100%). A
    ; fixed pixel guess like that clips content or leaves dead space once
    ; the actual caption/border overhead differs (Windows theme, DPI) --
    ; same bug CMDT's window.asm hit and fixed the same way. Recover the
    ; TRUE client size at 96 DPI first (AdjustWindowRectExForDpi on an
    ; empty rect yields exactly the frame overhead, which we subtract from
    ; 700/550), then re-expand that client size at the real runtime DPI to
    ; get the correct total size regardless of theme/DPI.
    mov     dword ptr [rsp+78h], 0              ; RECT.left
    mov     dword ptr [rsp+7Ch], 0              ; RECT.top
    mov     dword ptr [rsp+80h], 0              ; RECT.right
    mov     dword ptr [rsp+84h], 0              ; RECT.bottom
    lea     rcx, [rsp+78h]                      ; lpRect
    mov     edx, (STY_MAINWIN + WS_CLIPCHILDREN); dwStyle
    xor     r8d, r8d                            ; bMenu = FALSE
    xor     r9d, r9d                            ; dwExStyle = 0
    mov     dword ptr [rsp+20h], 96             ; dpi = 96 (5th param, on stack)
    call    AdjustWindowRectExForDpi

    call    GetDpiForSystem
    mov     dword ptr [rsp+88h], eax            ; stash runtime dpi

    ; Compute both overhead deltas from the 1st-call RECT BEFORE touching
    ; any of its fields (left/top can be negative, e.g. -31 for a caption,
    ; so they must be read as signed values here, not assumed zero).
    mov     eax, dword ptr [rsp+80h]
    sub     eax, dword ptr [rsp+78h]            ; overheadW96 = right - left
    mov     edx, dword ptr [rsp+84h]
    sub     edx, dword ptr [rsp+7Ch]            ; overheadH96 = bottom - top

    mov     ecx, 700
    sub     ecx, eax                            ; clientW96 = 700 - overheadW96
    mov     r10d, 550
    sub     r10d, edx                           ; clientH96 = 550 - overheadH96

    ; AdjustWindowRectExForDpi does NOT scale the client rect it's given --
    ; it only adds correctly-sized frame/caption padding for the requested
    ; DPI. The client size itself must be scaled by hand first (same
    ; val*dpi/96 pattern as every control in layout.asm), or the window
    ; barely grows at all while the DPI-scaled controls inside it do, and
    ; content overflows past the right edge -- exactly the bug reported
    ; after the first pass of this fix.
    mov     eax, ecx
    imul    eax, dword ptr [rsp+88h]
    mov     ecx, 96
    cdq
    idiv    ecx
    mov     r11d, eax                           ; clientW_runtime

    mov     eax, r10d
    imul    eax, dword ptr [rsp+88h]
    mov     ecx, 96
    cdq
    idiv    ecx
    mov     r10d, eax                           ; clientH_runtime

    mov     dword ptr [rsp+78h], 0              ; reuse RECT for the 2nd call
    mov     dword ptr [rsp+7Ch], 0
    mov     dword ptr [rsp+80h], r11d           ; RECT.right = clientW_runtime
    mov     dword ptr [rsp+84h], r10d           ; RECT.bottom = clientH_runtime

    lea     rcx, [rsp+78h]                       ; lpRect (now {0,0,clientW_runtime,clientH_runtime})
    mov     edx, (STY_MAINWIN + WS_CLIPCHILDREN)
    xor     r8d, r8d
    xor     r9d, r9d
    mov     eax, dword ptr [rsp+88h]
    mov     dword ptr [rsp+20h], eax             ; dpi = runtime dpi
    call    AdjustWindowRectExForDpi

    mov     eax, dword ptr [rsp+80h]
    sub     eax, dword ptr [rsp+78h]             ; final total width
    mov     dword ptr [rsp+88h], eax             ; stash (rsp+30h gets clobbered below)
    mov     eax, dword ptr [rsp+84h]
    sub     eax, dword ptr [rsp+7Ch]             ; final total height
    mov     dword ptr [rsp+8Ch], eax

    mov     rax, g_hInstance
    mov     qword ptr [rsp+58h], 0              ; lpParam = NULL
    mov     qword ptr [rsp+50h], rax            ; hInstance
    mov     qword ptr [rsp+48h], 0              ; hMenu = NULL
    mov     qword ptr [rsp+40h], 0              ; hWndParent = NULL (top-level)
    mov     eax, dword ptr [rsp+8Ch]
    mov     dword ptr [rsp+38h], eax            ; nHeight
    mov     eax, dword ptr [rsp+88h]
    mov     dword ptr [rsp+30h], eax            ; nWidth
    mov     dword ptr [rsp+28h], 080000000h     ; Y = CW_USEDEFAULT
    mov     dword ptr [rsp+20h], 080000000h     ; X = CW_USEDEFAULT
    mov     r9d, (STY_MAINWIN + WS_CLIPCHILDREN)
    cmp     g_startMinimized, 0
    je      @cmw_style_ok
    and     r9d, NOT WS_VISIBLE                 ; /tray: create hidden, no flash
@cmw_style_ok:
    lea     r8, str_title                       ; lpWindowName
    lea     rdx, str_wndclass                   ; lpClassName
    xor     ecx, ecx                            ; dwExStyle = 0
    call    CreateWindowExW
    test    rax, rax
    jz      @cmw_fail

    mov     rbx, rax

    cmp     g_startMinimized, 0
    jne     @cmw_tray           ; /tray: _TrayAdd in mode_gui will handle show

    mov     edx, SW_SHOWNORMAL
    mov     rcx, rbx
    call    ShowWindow

    mov     rcx, rbx
    call    UpdateWindow

@cmw_tray:
    mov     rax, rbx
    jmp     @cmw_ret

@cmw_fail:
    xor     eax, eax
@cmw_ret:
    add     rsp, 98h
    pop     rsi
    pop     rbx
    ret
CreateMainWindow endp

end
