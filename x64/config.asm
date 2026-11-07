; ==============================================================================
; Vault Guard - Registry Config Persistence
;
; Author: Marek Wesołowski (wesmar)
; Registry root: HKCU\Software\VG
;   \Paths   value_name=path(WCHAR*), type=REG_DWORD, data=flags(DWORD)
;   \Trusted value_name=name(WCHAR*), type=REG_DWORD, data=1
;
; Exported:
;   ConfigLoad()                 — restore all entries from registry → driver
;   ConfigSavePath(path, flags)  — rcx=WCHAR*, edx=DWORD
;   ConfigRemovePath(path)       — rcx=WCHAR*
;   ConfigSaveTrusted(name)      — rcx=WCHAR*
;   ConfigRemoveTrusted(name)    — rcx=WCHAR*
;   ConfigTrustedCanAdd(name, hwndOwner) — eax=1 if the entry fits in the driver
;                                  list, else shows a message and returns 0
;   ConfigDeleteAll()            — delete known HKCU\Software\VG config keys
; ==============================================================================

option casemap:none
include consts.inc
include globals.inc

EXTRN RegCreateKeyExW   :PROC
EXTRN RegOpenKeyExW     :PROC
EXTRN RegSetValueExW    :PROC
EXTRN RegDeleteValueW   :PROC
EXTRN RegDeleteKeyW     :PROC
EXTRN GetWindowsDirectoryW :PROC
EXTRN RegEnumValueW     :PROC
EXTRN RegCloseKey       :PROC
EXTRN EnsureDriverReady :PROC
EXTRN CloseDevice       :PROC
EXTRN IoctlAddPath      :PROC
EXTRN IoctlAddTrusted   :PROC
EXTRN IoctlBuildPathRecord     :PROC
EXTRN IoctlSendPathBuffer      :PROC
EXTRN IoctlSendTrustedBuffer   :PROC
EXTRN wcs_ascii_lower_inplace :PROC
EXTRN wcscpy_p          :PROC
EXTRN wcscmp_ci         :PROC
EXTRN MessageBoxW       :PROC

.data?
    cfg_hkey     dq ?           ; phkResult scratch
    cfg_disp     dd ?           ; lpdwDisposition scratch
    cfg_type     dd ?           ; value type scratch
    cfg_namelen  dd ?           ; lpcchValueName for RegEnumValueW
    cfg_datalen  dd ?           ; lpcbData for RegEnumValueW
    cfg_flags    dd ?           ; value data (flags DWORD)

    cfg_name_buf dw 520 dup(?)  ; value name / path buffer (MAX_PATH+1 WCHARs)

.const
    str_key_paths   dw 'S','o','f','t','w','a','r','e','\','V','G','\','P','a','t','h','s',0
    str_key_trusted dw 'S','o','f','t','w','a','r','e','\','V','G','\','T','r','u','s','t','e','d',0
    str_key_root    dw 'S','o','f','t','w','a','r','e','\','V','G',0
    str_lim_title   dw 'V','a','u','l','t',' ','G','u','a','r','d',0
    str_lim_trusted dw 'T','h','e',' ','t','r','u','s','t','e','d',' ','p','r','o','c','e','s','s',' '
                    dw 'l','i','s','t',' ','i','s',' ','f','u','l','l','.',' '
                    dw 'R','e','m','o','v','e',' ','o','r',' ','d','i','s','a','b','l','e',' ','a','n',' '
                    dw 'e','n','t','r','y',' ','b','e','f','o','r','e',' ','a','d','d','i','n','g',' '
                    dw 'a','n','o','t','h','e','r','.',0

.code

; ==============================================================================
; _CfgCreate  rcx=subkey(WCHAR*)  →  rax=HKEY or 0
; RegCreateKeyExW(HKCU, subkey, 0, NULL, 0, KEY_ALL_ACCESS, NULL,
;                 &cfg_hkey, &cfg_disp)
; Stack: entry rsp%16=8; push rbx (+8)→0; sub 50h (+80)→0 ✓
; RegCreateKeyExW 9 args: stack args at [rsp+20h]..[rsp+40h] (5 slots)
; ==============================================================================
_CfgCreate proc
    push    rbx
    sub     rsp, 50h

    mov     rbx, rcx                        ; save subkey ptr

    lea     rax, cfg_disp
    mov     qword ptr [rsp+40h], rax        ; lpdwDisposition
    lea     rax, cfg_hkey
    mov     qword ptr [rsp+38h], rax        ; phkResult
    mov     qword ptr [rsp+30h], 0          ; lpSecurityAttributes = NULL
    mov     dword ptr [rsp+28h], KEY_ALL_ACCESS
    mov     dword ptr [rsp+20h], REG_OPTION_NON_VOLATILE
    xor     r9d, r9d                        ; lpClass = NULL
    xor     r8d, r8d                        ; Reserved = 0
    mov     rdx, rbx                        ; lpSubKey
    mov     rcx, HKEY_CURRENT_USER
    call    RegCreateKeyExW
    test    eax, eax
    jnz     @cc_fail
    mov     rax, cfg_hkey
    jmp     @cc_ret
@cc_fail:
    xor     eax, eax
@cc_ret:
    add     rsp, 50h
    pop     rbx
    ret
_CfgCreate endp

; ==============================================================================
; _CfgOpen  rcx=subkey(WCHAR*)  →  rax=HKEY or 0 (0 if key does not exist)
; RegOpenKeyExW(HKCU, subkey, 0, KEY_READ, &cfg_hkey)
; Stack: entry rsp%16=8; push rbx (+8)→0; sub 30h (+48)→0 ✓
; RegOpenKeyExW 5 args: 1 stack arg at [rsp+20h]
; ==============================================================================
_CfgOpen proc
    push    rbx
    sub     rsp, 30h

    mov     rbx, rcx

    lea     rax, cfg_hkey
    mov     qword ptr [rsp+20h], rax        ; phkResult
    mov     r9d, KEY_READ
    xor     r8d, r8d                        ; ulOptions = 0
    mov     rdx, rbx
    mov     rcx, HKEY_CURRENT_USER
    call    RegOpenKeyExW
    test    eax, eax
    jnz     @co_fail
    mov     rax, cfg_hkey
    jmp     @co_ret
@co_fail:
    xor     eax, eax
@co_ret:
    add     rsp, 30h
    pop     rbx
    ret
_CfgOpen endp

; ==============================================================================
; ConfigSavePath  rcx=path(WCHAR*)  edx=flags(DWORD)  →  void
; HKCU\Software\VG\Paths\<path> = flags (REG_DWORD)
; Stack: entry rsp%16=8; push rbx,rsi,rdi (+24)→0; sub 50h (+80)→0 ✓
; RegSetValueExW 6 args: 2 stack args at [rsp+20h],[rsp+28h]
; ==============================================================================
PUBLIC ConfigSavePath
ConfigSavePath proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 50h

    mov     rbx, rcx                ; path
    mov     esi, edx                ; flags

    lea     rcx, str_key_paths
    call    _CfgCreate
    test    rax, rax
    jz      @csp_ret
    mov     rdi, rax                ; hKey

    ; cfg_flags ← esi  (lpData must point to stable memory through the call)
    lea     rax, cfg_flags
    mov     dword ptr [rax], esi

    lea     rax, cfg_flags
    mov     dword ptr [rsp+28h], 4          ; cbData = sizeof(DWORD)
    mov     qword ptr [rsp+20h], rax        ; lpData = &cfg_flags
    mov     r9d, REG_DWORD
    xor     r8d, r8d                        ; Reserved = 0
    mov     rdx, rbx                        ; lpValueName = path
    mov     rcx, rdi
    call    RegSetValueExW

    mov     rcx, rdi
    call    RegCloseKey

@csp_ret:
    add     rsp, 50h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ConfigSavePath endp

; ==============================================================================
; ConfigRemovePath  rcx=path(WCHAR*)  →  void
; Deletes HKCU\Software\VG\Paths\<path>.
; Stack: entry rsp%16=8; push rbx,rsi,rdi (+24)→0; sub 50h (+80)→0 ✓
; ==============================================================================
PUBLIC ConfigRemovePath
ConfigRemovePath proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 50h

    mov     rbx, rcx

    lea     rcx, str_key_paths
    call    _CfgCreate
    test    rax, rax
    jz      @crp_ret
    mov     rdi, rax

    mov     rdx, rbx
    mov     rcx, rdi
    call    RegDeleteValueW

    mov     rcx, rdi
    call    RegCloseKey

@crp_ret:
    add     rsp, 50h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ConfigRemovePath endp

; ==============================================================================
; ConfigSaveTrusted  rcx=name(WCHAR*)  →  void
; HKCU\Software\VG\Trusted\<name> = 1 (REG_DWORD)
; Stack: entry rsp%16=8; push rbx,rsi,rdi (+24)→0; sub 50h (+80)→0 ✓
; ==============================================================================
PUBLIC ConfigSaveTrusted
ConfigSaveTrusted proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 50h

    mov     rbx, rcx

    lea     rcx, str_key_trusted
    call    _CfgCreate
    test    rax, rax
    jz      @cst_ret
    mov     rdi, rax

    lea     rax, cfg_flags
    mov     dword ptr [rax], 1              ; value = 1 (Enabled)

    lea     rax, cfg_flags
    mov     dword ptr [rsp+28h], 4
    mov     qword ptr [rsp+20h], rax
    mov     r9d, REG_DWORD
    xor     r8d, r8d
    mov     rdx, rbx
    mov     rcx, rdi
    call    RegSetValueExW

    mov     rcx, rdi
    call    RegCloseKey

@cst_ret:
    add     rsp, 50h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ConfigSaveTrusted endp

; ==============================================================================
; ConfigRemoveTrusted  rcx=name(WCHAR*)  →  void
; Deletes HKCU\Software\VG\Trusted\<name>.
; Stack: entry rsp%16=8; push rbx,rsi,rdi (+24)→0; sub 50h (+80)→0 ✓
; ==============================================================================
PUBLIC ConfigRemoveTrusted
ConfigRemoveTrusted proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 50h

    mov     rbx, rcx

    lea     rcx, str_key_trusted
    call    _CfgCreate
    test    rax, rax
    jz      @crt_ret
    mov     rdi, rax

    mov     rdx, rbx
    mov     rcx, rdi
    call    RegDeleteValueW

    mov     rcx, rdi
    call    RegCloseKey

@crt_ret:
    add     rsp, 50h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ConfigRemoveTrusted endp

; ==============================================================================
; ConfigDeleteAll  →  void
; Deletes known HKCU\Software\VG config keys.  Used only by full product
; uninstall; normal item/trusted changes stay value-scoped above.
; Stack: entry rsp%16=8; sub 28h → 0 ✓
; ==============================================================================
PUBLIC ConfigDeleteAll
ConfigDeleteAll proc
    sub     rsp, 28h

    lea     rdx, str_key_paths
    mov     rcx, HKEY_CURRENT_USER
    call    RegDeleteKeyW

    lea     rdx, str_key_trusted
    mov     rcx, HKEY_CURRENT_USER
    call    RegDeleteKeyW

    lea     rdx, str_key_root
    mov     rcx, HKEY_CURRENT_USER
    call    RegDeleteKeyW

    add     rsp, 28h
    ret
ConfigDeleteAll endp

; ==============================================================================
; ConfigLoad  →  void
; Enumerates each registry key, builds one packed record array, then replaces the
; corresponding complete driver list with a single IOCTL.  The driver's 0x400
; and 0x408 handlers are SET operations, not append operations.
; Stack: 6 pushes leave rsp%16=8; sub 58h leaves rsp%16=0.
; ==============================================================================
PUBLIC ConfigLoad
ConfigLoad proc
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    sub     rsp, 58h

    ; ── Paths: build packed VG_PATH_RECORD array in g_ioBuf ───────────────────
    lea     rdi, g_ioBuf
    xor     eax, eax
    mov     ecx, VG_IOCTL_BUF_SIZE / 8
    rep     stosq
    xor     r12d, r12d                      ; active path record count

    ; Keep one syntactically valid flags=0 record in slot 0. The driver does
    ; not clear the last path for a completely zero-filled buffer, but it does
    ; clear the list when parsing a valid path record whose flags are zero.
    ; Any active path below overwrites this slot.
    mov     edx, 520
    lea     rcx, cfg_name_buf
    call    GetWindowsDirectoryW             ; normally C:\Windows
    test    eax, eax
    jz      @cl_paths_open
    cmp     eax, 3
    jb      @cl_paths_open
    mov     word ptr [cfg_name_buf + 6], 0  ; keep drive root, e.g. C:\
    lea     r8, cfg_name_buf
    xor     edx, edx
    lea     rcx, g_ioBuf
    call    IoctlBuildPathRecord

@cl_paths_open:
    lea     rcx, str_key_paths
    call    _CfgOpen
    mov     rbx, rax                         ; hKey or 0
    test    rbx, rbx
    jz      @cl_paths_apply
    xor     esi, esi                         ; registry index

@cl_paths_loop:
    mov     cfg_namelen, 520
    mov     cfg_datalen, 4
    lea     rax, cfg_datalen
    mov     qword ptr [rsp+38h], rax
    lea     rax, cfg_flags
    mov     qword ptr [rsp+30h], rax
    lea     rax, cfg_type
    mov     qword ptr [rsp+28h], rax
    mov     qword ptr [rsp+20h], 0
    lea     r9, cfg_namelen
    lea     r8, cfg_name_buf
    mov     edx, esi
    mov     rcx, rbx
    call    RegEnumValueW
    cmp     eax, ERROR_NO_MORE_ITEMS
    je      @cl_paths_apply
    test    eax, eax
    jnz     @cl_paths_next

    mov     r13d, cfg_flags
    test    r13d, VG_FLAG_DISABLED
    jnz     @cl_paths_next
    and     r13d, 0Fh
    jz      @cl_paths_next
    cmp     r12d, (VG_IOCTL_BUF_SIZE / VG_PATH_RECORD_SIZE)
    jae     @cl_paths_next                  ; buffer capacity reached

    mov     eax, r12d
    imul    eax, VG_PATH_RECORD_SIZE
    lea     rcx, g_ioBuf
    add     rcx, rax                        ; destination record
    mov     edx, r13d
    lea     r8, cfg_name_buf
    call    IoctlBuildPathRecord
    test    eax, eax
    jz      @cl_paths_next
    inc     r12d

@cl_paths_next:
    inc     esi
    jmp     @cl_paths_loop

@cl_paths_apply:
    call    EnsureDriverReady
    test    eax, eax
    jz      @cl_paths_close_key

    ; Preserve the original five-record minimum.  Larger arrays are accepted
    ; by the driver and fit in g_ioBuf up to its fixed capacity.
    mov     edx, VG_ORIG_PATH_INPUT_SIZE
    cmp     r12d, 5
    jbe     @cl_paths_send
    mov     edx, r12d
    imul    edx, VG_PATH_RECORD_SIZE
@cl_paths_send:
    lea     rcx, g_ioBuf
    call    IoctlSendPathBuffer
    call    CloseDevice

@cl_paths_close_key:
    test    rbx, rbx
    jz      @cl_do_trusted
    mov     rcx, rbx
    call    RegCloseKey

    ; ── Trusted: build packed VG_TRUSTED_RECORD array in g_ioBuf ──────────────
@cl_do_trusted:
    lea     rdi, g_ioBuf
    xor     eax, eax
    mov     ecx, VG_IOCTL_BUF_SIZE / 8
    rep     stosq
    xor     r12d, r12d                      ; active trusted record count

    lea     rcx, str_key_trusted
    call    _CfgOpen
    mov     rbx, rax
    test    rbx, rbx
    jz      @cl_trusted_apply
    xor     esi, esi

@cl_trusted_loop:
    mov     cfg_namelen, 520
    mov     cfg_datalen, 4

    lea     rax, cfg_datalen
    mov     qword ptr [rsp+38h], rax
    lea     rax, cfg_flags
    mov     qword ptr [rsp+30h], rax
    lea     rax, cfg_type
    mov     qword ptr [rsp+28h], rax
    mov     qword ptr [rsp+20h], 0
    lea     r9, cfg_namelen
    lea     r8, cfg_name_buf
    mov     edx, esi
    mov     rcx, rbx
    call    RegEnumValueW
    cmp     eax, ERROR_NO_MORE_ITEMS
    je      @cl_trusted_apply
    test    eax, eax
    jnz     @cl_trusted_next

    mov     ecx, cfg_flags
    test    ecx, ecx
    jz      @cl_trusted_next
    cmp     r12d, (VG_IOCTL_BUF_SIZE / VG_TRUSTED_RECORD_SIZE)
    jae     @cl_trusted_next

    lea     rcx, cfg_name_buf
    call    wcs_ascii_lower_inplace
    mov     word ptr [cfg_name_buf + 398], 0 ; driver name field is 200 WCHARs

    mov     eax, r12d
    imul    eax, VG_TRUSTED_RECORD_SIZE
    lea     rcx, [g_ioBuf + VG_TRUSTED_RECORD_NAME]
    add     rcx, rax
    lea     rdx, cfg_name_buf
    call    wcscpy_p
    inc     r12d

@cl_trusted_next:
    inc     esi
    jmp     @cl_trusted_loop

@cl_trusted_apply:
    call    EnsureDriverReady
    test    eax, eax
    jz      @cl_trusted_close_key
    mov     edx, r12d
    imul    edx, VG_TRUSTED_RECORD_SIZE
    lea     rcx, g_ioBuf
    call    IoctlSendTrustedBuffer
    call    CloseDevice

@cl_trusted_close_key:
    test    rbx, rbx
    jz      @cl_done
    mov     rcx, rbx
    call    RegCloseKey

@cl_done:
    add     rsp, 58h
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ConfigLoad endp

; ==============================================================================
; ConfigTrustedCanAdd  rcx=name(WCHAR*)  rdx=hwndOwner  →  eax=1 allowed / 0 denied
; ConfigLoad can push at most VG_IOCTL_BUF_SIZE / VG_TRUSTED_RECORD_SIZE active
; trusted records to the driver (g_ioBuf capacity); anything beyond is skipped.
; Call this BEFORE saving a new/re-enabled trusted entry so the GUI never shows
; an entry that the driver does not enforce.  The count uses the same rule as
; ConfigLoad (registry value data != 0).  An entry that is already active under
; the same name does not grow the list and is therefore always allowed.
; On denial a warning MessageBox is shown (owner = rdx, may be 0).
; Stack: 5 pushes leave rsp%16=0; sub 50h keeps it 0 (8-arg RegEnumValueW fits).
; ==============================================================================
PUBLIC ConfigTrustedCanAdd
ConfigTrustedCanAdd proc
    push    rbx
    push    rsi
    push    rdi
    push    r12
    push    r13
    sub     rsp, 50h

    mov     rdi, rcx                        ; name being added
    mov     r13, rdx                        ; owner window
    xor     r12d, r12d                      ; active trusted count

    lea     rcx, str_key_trusted
    call    _CfgOpen
    mov     rbx, rax
    test    rbx, rbx
    jz      @ctca_ok                        ; no key yet → list is empty
    xor     esi, esi

@ctca_loop:
    mov     cfg_namelen, 520
    mov     cfg_datalen, 4

    lea     rax, cfg_datalen
    mov     qword ptr [rsp+38h], rax
    lea     rax, cfg_flags
    mov     qword ptr [rsp+30h], rax
    lea     rax, cfg_type
    mov     qword ptr [rsp+28h], rax
    mov     qword ptr [rsp+20h], 0
    lea     r9, cfg_namelen
    lea     r8, cfg_name_buf
    mov     edx, esi
    mov     rcx, rbx
    call    RegEnumValueW
    cmp     eax, ERROR_NO_MORE_ITEMS
    je      @ctca_done
    test    eax, eax
    jnz     @ctca_next

    mov     ecx, cfg_flags
    test    ecx, ecx
    jz      @ctca_next                      ; disabled entries are not sent to driver

    lea     rcx, cfg_name_buf
    mov     rdx, rdi
    call    wcscmp_ci
    test    rax, rax
    jz      @ctca_close_ok                  ; same name already active → no growth
    inc     r12d

@ctca_next:
    inc     esi
    jmp     @ctca_loop

@ctca_done:
    mov     rcx, rbx
    call    RegCloseKey
    cmp     r12d, (VG_IOCTL_BUF_SIZE / VG_TRUSTED_RECORD_SIZE)
    jb      @ctca_ok

    mov     r9d, MB_OK + MB_ICONWARNING
    lea     r8, str_lim_title
    lea     rdx, str_lim_trusted
    mov     rcx, r13
    call    MessageBoxW
    xor     eax, eax
    jmp     @ctca_ret

@ctca_close_ok:
    mov     rcx, rbx
    call    RegCloseKey
@ctca_ok:
    mov     eax, 1
@ctca_ret:
    add     rsp, 50h
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ConfigTrustedCanAdd endp

; ==============================================================================
; ConfigSaveTrustedEx  rcx=name(WCHAR*)  edx=value(DWORD)  →  void
; HKCU\Software\VG\Trusted\<name> = value (REG_DWORD). value=1 means enabled, 0 disabled.
; Stack: entry rsp%16=8; push rbx,rsi,rdi (+24)→0; sub 50h (+80)→0 ✓
; ==============================================================================
PUBLIC ConfigSaveTrustedEx
ConfigSaveTrustedEx proc
    push    rbx
    push    rsi
    push    rdi
    sub     rsp, 50h

    mov     rbx, rcx                ; name
    mov     esi, edx                ; value (0 or 1)

    lea     rcx, str_key_trusted
    call    _CfgCreate
    test    rax, rax
    jz      @cstx_ret
    mov     rdi, rax

    lea     rax, cfg_flags
    mov     dword ptr [rax], esi    ; store value

    lea     rax, cfg_flags
    mov     dword ptr [rsp+28h], 4
    mov     qword ptr [rsp+20h], rax
    mov     r9d, REG_DWORD
    xor     r8d, r8d
    mov     rdx, rbx
    mov     rcx, rdi
    call    RegSetValueExW

    mov     rcx, rdi
    call    RegCloseKey

@cstx_ret:
    add     rsp, 50h
    pop     rdi
    pop     rsi
    pop     rbx
    ret
ConfigSaveTrustedEx endp

end
