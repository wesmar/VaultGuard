; ==============================================================================
; Vault Guard - Entry Point and Global Data
;
; Author: Marek Wesołowski (wesmar)
; Purpose: Process entry, global data, message loop.
;          mainCRTStartup attaches console, parses argv, dispatches to
;          CliDispatch (argv[1], argv, argc) or falls through to mode_gui.
; ==============================================================================

option casemap:none

include consts.inc

EXTRN GetModuleHandleW      :PROC
EXTRN GetMessageW           :PROC
EXTRN TranslateMessage      :PROC
EXTRN DispatchMessageW      :PROC
EXTRN ExitProcess           :PROC
EXTRN AttachConsole         :PROC
EXTRN GetStdHandle          :PROC
EXTRN GetFileType           :PROC
EXTRN GetCommandLineW       :PROC
EXTRN CommandLineToArgvW    :PROC
EXTRN LocalFree             :PROC

EXTRN CreateMainWindow      :PROC
EXTRN CliDispatch           :PROC
EXTRN _TrayAdd              :PROC

; ==============================================================================
; INITIALIZED DATA
; ==============================================================================
.data
    align 8

PUBLIC g_hInstance, g_hwndMain
PUBLIC g_hwndLvPaths, g_hwndLvTrusted
PUBLIC g_hwndBtnToggle
PUBLIC g_hwndDrvStatus, g_hwndProtStatus
PUBLIC g_hDevice
PUBLIC g_hFontMain, g_hFontSmall
PUBLIC g_hBrushBg
PUBLIC g_isDarkMode
PUBLIC g_driverInstalled, g_driverRunning, g_protActive
PUBLIC g_cliMode
PUBLIC g_prevDrvOk, g_prevProtActive
PUBLIC g_startMinimized

g_hInstance         dq 0
g_hwndMain          dq 0
g_hwndLvPaths       dq 0
g_hwndLvTrusted     dq 0
g_hwndBtnToggle     dq 0
g_hwndDrvStatus     dq 0
g_hwndProtStatus    dq 0
g_hDevice           dq 0
g_hFontMain         dq 0
g_hFontSmall        dq 0
g_hBrushBg          dq 0
g_isDarkMode        dd 1        ; default dark
                    dd 0
g_driverInstalled   dd 0
                    dd 0
g_driverRunning     dd 0
                    dd 0
g_protActive        dd 0
                    dd 0
g_cliMode           dd 0
                    dd 0
g_startMinimized    dd 0
                    dd 0
; State cache for UpdateStatusBar — prevents flicker on unchanged labels.
; 0xFF = sentinel "never set", forces update on first call.
g_prevDrvOk         db 0FFh
                    db 0, 0, 0
g_prevProtActive    db 0FFh
                    db 0, 0, 0

; ==============================================================================
; UNINITIALIZED DATA
; ==============================================================================
.data?

PUBLIC g_ioBuf, g_pathBuf, g_tempBuf, g_statusBuf

g_ioBuf     db VG_IOCTL_BUF_SIZE dup(?)    ; 128 KB IOCTL buffer
g_pathBuf   dw 520 dup(?)                  ; path edit scratch (MAX_PATH+1)
g_tempBuf   dw 520 dup(?)                  ; general scratch
g_statusBuf dw 520 dup(?)                  ; status text scratch

; ==============================================================================
; CODE
; ==============================================================================
.code

; ==============================================================================
; mainCRTStartup - Process Entry Point
;
; Attaches to parent console if needed. Parses argv; if argc >= 2, calls
; CliDispatch(argv[1], argv, argc). On unknown switch CliDispatch returns 0
; and we fall through to GUI mode.
;
; Stack: entry rsp%16=8; push rbx,rsi,rdi,r12 (32)→rsp%16=8;
;        sub 38h (56) → rsp%16=0 ✓
; [rsp+20h] = argc (DWORD, written by CommandLineToArgvW via rdx)
; [rsp+24h] = padding
; rbx = argv (WCHAR**)
; r12 = stdout handle (for console attach check)
; ==============================================================================
PUBLIC mainCRTStartup
mainCRTStartup proc
    push    rbx
    push    rsi
    push    rdi
    push    r12
    sub     rsp, 38h

    ; Check stdout: attach console only when missing or already a real console
    mov     ecx, STD_OUTPUT_HANDLE
    call    GetStdHandle
    test    rax, rax
    jz      @mcs_attach                 ; no stdout handle -- attach
    cmp     rax, INVALID_HANDLE_VALUE
    je      @mcs_attach
    mov     rcx, rax
    call    GetFileType                  ; FILE_TYPE_CHAR = real console
    cmp     eax, FILE_TYPE_CHAR
    jne     @mcs_no_attach              ; piped/redirected -- do not attach

@mcs_attach:
    mov     ecx, ATTACH_PARENT_PROCESS
    call    AttachConsole

@mcs_no_attach:
    ; Parse command line into argv/argc
    call    GetCommandLineW
    lea     rdx, [rsp+20h]          ; &argc (written by CommandLineToArgvW)
    mov     rcx, rax
    call    CommandLineToArgvW
    test    rax, rax
    jz      @mcs_gui                ; parse failed -- fall through to GUI
    mov     rbx, rax                ; rbx = argv (array of WCHAR*)

    cmp     dword ptr [rsp+20h], 2
    jl      @mcs_free_gui           ; argc < 2 → GUI

    ; CliDispatch(argv[1], argv, argc) -- handles /add, /remove, /status etc.
    mov     r8d, dword ptr [rsp+20h]    ; argc
    mov     rdx, rbx                    ; argv
    mov     rcx, [rbx + 8]              ; argv[1] = first switch
    call    CliDispatch
    ; returns 0 for unknown switch → fall through to GUI mode

@mcs_free_gui:
    mov     rcx, rbx
    call    LocalFree

@mcs_gui:
    add     rsp, 38h
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    jmp     mode_gui

mainCRTStartup endp

; ==============================================================================
; mode_gui - GUI Mode
;
; Gets hInstance, creates window, runs message loop until WM_QUIT.
; Reached via tail-jump from mainCRTStartup (rsp%16=8 at entry).
;
; Stack: entry rsp%16=8; sub 58h (88) → rsp%16=0 ✓
; MSG at [rsp+20h] (48 bytes = 3×QWORD + rest)
; ==============================================================================
PUBLIC mode_gui
mode_gui proc
    sub     rsp, 58h

    xor     ecx, ecx                ; lpModuleName = NULL -> this EXE
    call    GetModuleHandleW
    mov     g_hInstance, rax        ; store hInstance for class registration

    call    CreateMainWindow        ; register class, create window, show
    test    rax, rax
    jz      @mg_exit                ; NULL = creation failed, exit cleanly

    cmp     g_startMinimized, 0
    je      @mg_loop
    mov     rcx, rax                ; hwnd
    call    _TrayAdd                ; /tray flag: hide to tray immediately

@mg_loop:
    lea     rcx, [rsp+20h]          ; lpMsg
    xor     edx, edx                ; hWnd = NULL (all windows)
    xor     r8d, r8d                ; wMsgFilterMin = 0
    xor     r9d, r9d                ; wMsgFilterMax = 0
    call    GetMessageW
    test    eax, eax
    jz      @mg_exit                ; WM_QUIT -> eax = 0
    js      @mg_exit                ; error -> eax = -1

    lea     rcx, [rsp+20h]
    call    TranslateMessage        ; WM_KEYDOWN -> WM_CHAR etc.

    lea     rcx, [rsp+20h]
    call    DispatchMessageW        ; route to WndProc

    jmp     @mg_loop

@mg_exit:
    xor     ecx, ecx
    call    ExitProcess
mode_gui endp

end
