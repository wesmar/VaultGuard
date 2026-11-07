; ==============================================================================
; Vault Guard - Constants
; Author: Marek Wesołowski (wesmar)
; ==============================================================================

; ------------------------------------------------------------------------------
; IOCTL codes  (CTL_CODE = (type<<16)|(access<<14)|(func<<2)|method)
; VG_DEVICE_TYPE = 0x9C41
; ------------------------------------------------------------------------------
VG_DEVICE_TYPE              EQU 9C41h

IOCTL_VG_ADD_PATH           EQU 9C402400h   ; original: DWORD flags + NT path
IOCTL_VG_REMOVE_PATH        EQU 9C402400h   ; Disabled is ADD_PATH with flags=0
IOCTL_VG_ENUM_PATHS         EQU 9C402404h
IOCTL_VG_ADD_TRUSTED        EQU 9C402408h
IOCTL_VG_REMOVE_TRUSTED     EQU 9C402408h
IOCTL_VG_ENUM_TRUSTED       EQU 9C40240Ch
IOCTL_VG_SET_ACTIVE         EQU 9C40241Ch
IOCTL_VG_GET_STATUS         EQU 9C402420h
IOCTL_VG_CLEAR_ALL          EQU 9C402424h   ; original full sync/reload

; ------------------------------------------------------------------------------
; Protection flags (ProtectionMode bitmask)
; ------------------------------------------------------------------------------
VG_FLAG_HIDDEN              EQU 01h
VG_FLAG_LOCKED              EQU 02h
VG_FLAG_READONLY            EQU 04h
VG_FLAG_NOEXEC              EQU 08h
VG_FLAG_DISABLED            EQU 80h     ; bit 7: row kept in list but inactive in driver

; VG_PATH_ENTRY offsets (packed struct: 1+2+var)
VG_PE_FLAGS                 EQU 0           ; BYTE  Flags
VG_PE_PATHLEN               EQU 1           ; WORD  PathLengthBytes (excl. null)
VG_PE_PATH                  EQU 3           ; WCHAR Path[]

; VG_TRUSTED_ENTRY offsets
VG_TE_NAMELEN               EQU 0           ; WORD  NameLengthBytes
VG_TE_NAME                  EQU 2           ; WCHAR Name[]
VG_TRUSTED_RECORD_SIZE      EQU 0D94h       ; fixed trusted record size in clrcdsp.dat
VG_TRUSTED_RECORD_NAME      EQU 4           ; WCHAR process image name starts here
VG_PATH_RECORD_SIZE         EQU 01404h      ; DWORD flags + 0x800 + 0x800 + 0x400 byte fields

; VG_SET_ACTIVE offset
VG_SA_ACTIVE                EQU 0           ; BYTE  Active (1/0)

; VG_STATUS offsets
VG_ST_ISACTIVE              EQU 0           ; BYTE
VG_ST_PATHCOUNT             EQU 4           ; DWORD (aligned at 4 in struct — pad after byte)
VG_ST_TRUSTEDCOUNT          EQU 8           ; DWORD
VG_ST_VERSION               EQU 12          ; DWORD
VG_STATUS_SIZE              EQU 16          ; sizeof VG_STATUS (with packing)

; VG_ENUM_REPLY offsets
VG_ER_COUNT                 EQU 0           ; DWORD
VG_ER_TOTALBYTES            EQU 4           ; DWORD
VG_ER_ENTRIES               EQU 8           ; entries follow

; Buffers
VG_IOCTL_BUF_SIZE           EQU 131072      ; 128 KB: enum replies + trusted/path arrays (37 trusted, 25 paths)
VG_PATH_MAX_CHARS           EQU 32767       ; UNICODE_STRING max
VG_ORIG_PATH_INPUT_SIZE     EQU 06414h      ; 5 * VG_PATH_RECORD_SIZE

; ------------------------------------------------------------------------------
; SERVICE CONTROL MANAGER
; ------------------------------------------------------------------------------
SC_MANAGER_CREATE_SERVICE   EQU 0002h
SC_MANAGER_CONNECT          EQU 0001h
SC_MANAGER_ALL              EQU 000F003Fh
SERVICE_KERNEL_DRIVER       EQU 00000001h
SERVICE_AUTO_START          EQU 00000002h
SERVICE_DEMAND_START        EQU 00000003h
SERVICE_ERROR_NORMAL        EQU 00000001h
SERVICE_QUERY_STATUS        EQU 00000004h
SERVICE_START               EQU 00000010h
SERVICE_STOP                EQU 00000020h
SERVICE_DELETE_SVC          EQU 00010000h
SERVICE_CHANGE_CONFIG       EQU 00000002h
SERVICE_ALL_ACCESS          EQU 000F01FFh
SERVICE_NO_CHANGE           EQU 0FFFFFFFFh
SC_STATUS_PROCESS_INFO      EQU 0
SERVICE_STATUS_PROCESS_SIZE EQU 36
SERVICE_RUNNING             EQU 4
SERVICE_STOPPED             EQU 1
ERROR_SERVICE_ALREADY_RUNNING EQU 1056
ERROR_SERVICE_DOES_NOT_EXIST EQU 424h
ERROR_ALREADY_EXISTS        EQU 183
SERVICE_WIN32_OWN_PROCESS   EQU 00000010h
SERVICE_STOP_PENDING        EQU 3
SERVICE_CONTROL_STOP        EQU 00000001h
SERVICE_CONTROL_SHUTDOWN    EQU 5
SERVICE_CONTROL_PRESHUTDOWN EQU 0Fh
SERVICE_ACCEPT_STOP         EQU 1
SERVICE_ACCEPT_SHUTDOWN     EQU 4
SERVICE_ACCEPT_PRESHUTDOWN  EQU 100h
INFINITE                    EQU 0FFFFFFFFh
WAIT_FAILED_VAL             EQU 0FFFFFFFFh

; ------------------------------------------------------------------------------
; REGISTRY
; ------------------------------------------------------------------------------
HKEY_CURRENT_USER           EQU 0FFFFFFFF80000001h
HKEY_LOCAL_MACHINE          EQU 0FFFFFFFF80000002h
KEY_ALL_ACCESS              EQU 0F003Fh
KEY_READ                    EQU 20019h
KEY_SET_VALUE               EQU 00002h
REG_OPTION_NON_VOLATILE     EQU 0
REG_SZ                      EQU 1
REG_DWORD                   EQU 4
ERROR_NO_MORE_ITEMS         EQU 103h    ; 259 decimal

; ------------------------------------------------------------------------------
; COM / UIPI
; ------------------------------------------------------------------------------
CLSCTX_INPROC_SERVER        EQU 1
MSGFLT_ALLOW                EQU 1

; ------------------------------------------------------------------------------
; FILE / GENERIC
; ------------------------------------------------------------------------------
GENERIC_READ                EQU 80000000h
GENERIC_WRITE               EQU 40000000h
GENERIC_RW                  EQU 0C0000000h
FILE_SHARE_READ             EQU 00000001h
OPEN_EXISTING               EQU 3
CREATE_ALWAYS               EQU 2
FILE_ATTRIBUTE_NORMAL       EQU 00000080h
FILE_FLAG_OVERLAPPED        EQU 40000000h
INVALID_HANDLE_VALUE        EQU -1
CREATE_NO_WINDOW            EQU 08000000h

; ------------------------------------------------------------------------------
; WINDOW STYLES
; ------------------------------------------------------------------------------
DS_MODALFRAME               EQU 00000080h
DS_CENTER                   EQU 00000800h
WS_CAPTION                  EQU 00C00000h
WS_SYSMENU                  EQU 00080000h
WS_MINIMIZEBOX              EQU 00020000h
WS_CHILD                    EQU 40000000h
WS_VISIBLE                  EQU 10000000h
WS_TABSTOP                  EQU 00010000h
WS_CLIPCHILDREN             EQU 02000000h
WS_CLIPSIBLINGS             EQU 04000000h
WS_BORDER                   EQU 00800000h
WS_VSCROLL                  EQU 00200000h

STY_MAINWIN                 EQU 10CA0000h   ; CAPTION|SYSMENU|MINIMIZEBOX|VISIBLE
WS_CHILD_VISIBLE            EQU 50000000h
STY_BUTTON                  EQU 50010000h
STY_BUTTON_DEF              EQU 50010001h
STY_STATIC                  EQU 50000000h
STY_STATIC_CENTER           EQU 50000001h   ; WS_CHILD|WS_VISIBLE|SS_CENTER
STY_GROUPBOX                EQU 50000007h

; Extended styles
WS_EX_CLIENTEDGE            EQU 00000200h
WS_EX_CONTROLPARENT        EQU 00010000h

; ListView styles
LVS_REPORT                  EQU 0001h
LVS_SHOWSELALWAYS           EQU 0008h
LVS_SINGLESEL               EQU 0004h
LVS_EX_FULLROWSELECT        EQU 00000020h
LVS_EX_GRIDLINES            EQU 00000001h
LVS_EX_DOUBLEBUFFER         EQU 00010000h
LVS_EX_CHECKBOXES           EQU 00000004h

; CheckBox style
BS_CHECKBOX                 EQU 00000002h
BS_AUTOCHECKBOX             EQU 00000003h
BS_PUSHBUTTON               EQU 00000000h

; Edit box
ES_AUTOHSCROLL              EQU 00000080h
WS_EX_STATICEDGE            EQU 00020000h

; ------------------------------------------------------------------------------
; WINDOW CLASS STYLES
; ------------------------------------------------------------------------------
CS_HREDRAW                  EQU 0002h
CS_VREDRAW                  EQU 0001h

; ------------------------------------------------------------------------------
; DWM - dark mode / Mica
; ------------------------------------------------------------------------------
DWMWA_USE_IMMERSIVE_DARK_MODE     EQU 20
DWMWA_USE_IMMERSIVE_DARK_MODE_OLD EQU 19
DWMWA_SYSTEMBACKDROP_TYPE         EQU 38
DWMSBT_MAINWINDOW                 EQU 2

; ------------------------------------------------------------------------------
; WINDOW MESSAGES
; ------------------------------------------------------------------------------
WM_CREATE                   EQU 0001h
WM_DESTROY                  EQU 0002h
WM_CLOSE                    EQU 0010h
WM_COMMAND                  EQU 0111h
WM_NOTIFY                   EQU 004Eh
WM_COPYGLOBALDATA           EQU 0049h
WM_COPYDATA                 EQU 004Ah
WM_DROPFILES                EQU 0233h
WM_SETFONT                  EQU 0030h
WM_THEMECHANGED             EQU 031Ah
WM_CTLCOLORSTATIC           EQU 0138h
WM_CTLCOLORBTN              EQU 0135h
WM_CTLCOLOREDIT             EQU 0133h
WM_ERASEBKGND               EQU 0014h
WM_SIZE                     EQU 0005h
WM_TIMER                    EQU 0113h
WM_INITDIALOG               EQU 0110h
WM_SETREDRAW                EQU 000Bh
WM_SETTINGCHANGE            EQU 001Ah

; ListView notifications (NM_ = 0-...)
LVN_ITEMCHANGED             EQU 0FFFFFF9Bh  ; LVN_FIRST(-100) - 1 = -101
NM_DBLCLK                   EQU 0FFFFFFFDh  ; -3
NM_CLICK                    EQU 0FFFFFFFEh  ; -2
; LVM_FIRST = 0x1000 = 4096.  All offsets below are decimal (LVM_FIRST + N).
LVM_SETEXTENDEDLISTVIEWSTYLE EQU 1036h      ; LVM_FIRST+54
LVM_INSERTCOLUMNW           EQU 1061h       ; LVM_FIRST+97
LVM_INSERTITEMW             EQU 104Dh       ; LVM_FIRST+77
LVM_SETITEMW                EQU 104Ch       ; LVM_FIRST+76
LVM_GETITEMW                EQU 104Bh       ; LVM_FIRST+75
LVM_DELETEITEM              EQU 1008h       ; LVM_FIRST+8
LVM_DELETEALLITEMS          EQU 1009h       ; LVM_FIRST+9
LVM_GETITEMCOUNT            EQU 1004h       ; LVM_FIRST+4
LVM_GETITEMSTATE            EQU 102Ch       ; LVM_FIRST+44
LVM_GETNEXTITEM             EQU 100Ch       ; LVM_FIRST+12
LVM_GETITEMTEXTW            EQU 1073h       ; LVM_FIRST+115
LVM_SETBKCOLOR              EQU 1001h       ; LVM_FIRST+1
LVM_SETTEXTCOLOR            EQU 1024h       ; LVM_FIRST+36
LVM_SETTEXTBKCOLOR          EQU 1026h       ; LVM_FIRST+38
LVM_SETITEMSTATE            EQU 102Bh       ; LVM_FIRST+43
LVM_ENSUREVISIBLE           EQU 1013h       ; LVM_FIRST+19
LVS_EX_HEADERDRAGDROP       EQU 00000010h

LVIF_TEXT                   EQU 00000001h
LVIF_PARAM                  EQU 00000004h
LVIF_STATE                  EQU 00000008h
LVIS_SELECTED               EQU 0002h
LVIS_FOCUSED                EQU 0001h
LVNI_SELECTED               EQU 0002h
LVIS_STATEIMAGEMASK         EQU 0F000h
LVCHECKED                   EQU 2000h   ; INDEXTOSTATEIMAGEMASK(2)
LVUNCHECKED                 EQU 1000h   ; INDEXTOSTATEIMAGEMASK(1)

; NMLISTVIEW offsets (x64): NMHDR(24) + iItem(4) + iSubItem(4) + uNewState(4) + uOldState(4) + uChanged(4)
NMLV_uNewState              EQU 32
NMLV_uOldState              EQU 36
NMLV_uChanged               EQU 40

; LVCOLUMNW mask
LVCF_FMT                    EQU 0001h
LVCF_WIDTH                  EQU 0002h
LVCF_TEXT                   EQU 0004h
LVCF_SUBITEM                EQU 0008h
LVCFMT_LEFT                 EQU 0000h
LVCFMT_CENTER               EQU 0002h

; LVITEMW iSubItem for flag columns
LVITEM_COL_PATH             EQU 0
LVITEM_COL_H                EQU 1
LVITEM_COL_L                EQU 2
LVITEM_COL_R                EQU 3
LVITEM_COL_X                EQU 4

; LVITEMW struct offsets (x64)
LVITEMW_mask                EQU 0
LVITEMW_iItem               EQU 4
LVITEMW_iSubItem            EQU 8
LVITEMW_state               EQU 12
LVITEMW_stateMask           EQU 16
LVITEMW_pszText             EQU 24          ; pointer (8 bytes, aligned)
LVITEMW_cchTextMax          EQU 32
LVITEMW_iImage              EQU 36
LVITEMW_lParam              EQU 40          ; LPARAM (8 bytes)
LVITEMW_SIZE                EQU 56          ; sizeof LVITEMW x64

; LVCOLUMNW struct offsets (x64)
LVCOLUMNW_mask              EQU 0
LVCOLUMNW_fmt               EQU 4
LVCOLUMNW_cx                EQU 8
LVCOLUMNW_pszText           EQU 16          ; pointer
LVCOLUMNW_cchTextMax        EQU 24
LVCOLUMNW_iSubItem          EQU 28
LVCOLUMNW_SIZE              EQU 32

; ------------------------------------------------------------------------------
; CONTROL IDs
; ------------------------------------------------------------------------------
IDC_LV_PATHS                EQU 200
IDC_LV_TRUSTED              EQU 201
IDC_BTN_ADD_PATH            EQU 202
IDC_BTN_REM_PATH            EQU 203
IDC_BTN_ADD_TRUSTED         EQU 204
IDC_BTN_REM_TRUSTED         EQU 205
IDC_BTN_TOGGLE              EQU 206
IDC_STATIC_DRV_STATUS       EQU 209
IDC_STATIC_PROT_STATUS      EQU 210
IDC_STATIC_PATHS_HDR        EQU 211
IDC_STATIC_TRUSTED_HDR      EQU 212
IDC_EDIT_PATH               EQU 213
IDC_EDIT_TRUSTED            EQU 214
IDC_STATIC_AUTHOR           EQU 215         ; author / copyright label at bottom
IDC_BTN_ADD_RUNNING         EQU 216         ; "Add running" process picker
IDC_BTN_EXPORT              EQU 217
IDC_BTN_IMPORT              EQU 218
IDC_LV_PROCPICK             EQU 219         ; ListView inside process picker dialog

; Protection flags dialog control IDs
IDC_DLG_PATH                EQU 100
IDC_CHK_HIDDEN              EQU 101
IDC_CHK_LOCKED              EQU 102
IDC_CHK_READONLY            EQU 103
IDC_CHK_NOEXEC              EQU 104

; Timer ID for status refresh
TIMER_STATUS_ID             EQU 1
TIMER_STATUS_MS             EQU 2000

; ------------------------------------------------------------------------------
; MESSAGE BOX
; ------------------------------------------------------------------------------
MB_OK                       EQU 00000000h
MB_YESNO                    EQU 00000004h
MB_ICONERROR                EQU 00000010h
MB_ICONWARNING              EQU 00000030h
MB_ICONINFORMATION          EQU 00000040h
MB_ICONQUESTION             EQU 00000020h
IDOK                        EQU 1
IDCANCEL                    EQU 2
IDYES                       EQU 6
IDNO                        EQU 7
BST_CHECKED                 EQU 1

; ------------------------------------------------------------------------------
; MISC
; ------------------------------------------------------------------------------
SW_SHOWNORMAL               EQU 1
SW_HIDE                     EQU 0
SW_RESTORE                  EQU 9
SW_SHOW                     EQU 5
SIZE_MINIMIZED              EQU 1
VK_SHIFT                    EQU 10h
WM_TRAY                     EQU 8001h
WM_NULL                     EQU 0000h
WM_LBUTTONDBLCLK            EQU 0203h
WM_RBUTTONUP                EQU 0205h
NIM_ADD                     EQU 0
NIM_DELETE                  EQU 2
NIF_MESSAGE                 EQU 1
NIF_ICON                    EQU 2
NIF_TIP                     EQU 4
NID_CBSIZE                  EQU 168         ; NOTIFYICONDATAW v1 size on x64
MF_STRING                   EQU 0
MF_SEPARATOR                EQU 800h
TPM_RIGHTBUTTON             EQU 2
TPM_RETURNCMD               EQU 100h
IDM_TRAY_RESTORE            EQU 1
IDM_TRAY_EXIT               EQU 2
IDC_ARROW_ATOM              EQU 32512
WHITE_BRUSH                 EQU 0
NULL_BRUSH                  EQU 5
COLOR_WINDOW_VAL            EQU 5
COLOR_BTNFACE               EQU 15

; GDI colors
COLORREF_GREEN              EQU 00008000h   ; RGB(0,128,0)
COLORREF_RED                EQU 000000FFh   ; RGB(255,0,0)
COLORREF_ORANGE             EQU 0000A5FFh   ; RGB(255,165,0)
COLORREF_WHITE              EQU 00FFFFFFh
COLORREF_BLACK              EQU 00000000h
COLORREF_DARK_BG            EQU 00202020h   ; dark mode background
COLORREF_DARK_TEXT          EQU 00F0F0F0h   ; near-white text
COLORREF_DARK_LV_BG         EQU 002D2D2Dh   ; ListView dark background
COLORREF_ACCENT_BLUE        EQU 00CC7700h   ; accent (BGR: orange-ish)

CLR_DEFAULT                 EQU 0FFFFFFFFh  ; reset ListView color to system default

TRANSPARENT_VAL             EQU 1
OPAQUE_VAL                  EQU 2

; WNDCLASSEXW
WNDCLASSEXW_SIZE            EQU 80

; CommonControls
ICC_LISTVIEW_CLASSES        EQU 00000001h
INITCOMMONCONTROLSEX_SIZE   EQU 8

; BROWSEINFO struct size (x64)
BROWSEINFO_SIZE             EQU 72
BIF_RETURNONLYFSDIRS        EQU 0001h
BIF_NEWDIALOGSTYLE          EQU 0040h
BIF_USENEWUI                EQU 0050h
BIF_BROWSEINCLUDEFILES      EQU 4000h

; SHGetPathFromIDListW max
MAX_PATH                    EQU 260

; ------------------------------------------------------------------------------
; TOOLHELP32 — process enumeration
; ------------------------------------------------------------------------------
TH32CS_SNAPPROCESS          EQU 00000002h
PE32W_dwSize                EQU 0           ; DWORD
PE32W_th32ProcessID         EQU 8           ; DWORD (after cntUsage at 4)
PE32W_szExeFile             EQU 44          ; WCHAR[260] (after alignment pad + ULONG_PTR)
PROCESSENTRY32W_SIZE        EQU 568         ; sizeof PROCESSENTRY32W (x64)

; ------------------------------------------------------------------------------
; OPENFILENAMEW — GetOpenFileNameW / GetSaveFileNameW
; ------------------------------------------------------------------------------
OFN_SIZE                    EQU 136
OFN_lStructSize             EQU 0
OFN_hwndOwner               EQU 8
OFN_hInstance               EQU 16
OFN_lpstrFilter             EQU 24
OFN_lpstrCustomFilter       EQU 32
OFN_nMaxCustFilter          EQU 40
OFN_nFilterIndex            EQU 44
OFN_lpstrFile               EQU 48
OFN_nMaxFile                EQU 56
OFN_lpstrFileTitle          EQU 64
OFN_nMaxFileTitle           EQU 72
OFN_lpstrInitialDir         EQU 80
OFN_lpstrTitle              EQU 88
OFN_Flags                   EQU 96
OFN_lpstrDefExt             EQU 104
OFN_PATHMUSTEXIST           EQU 00000800h
OFN_FILEMUSTEXIST           EQU 00001000h
OFN_OVERWRITEPROMPT         EQU 00000002h
OFN_EXPLORER                EQU 00080000h
OFN_HIDEREADONLY            EQU 00000004h

; ------------------------------------------------------------------------------
; CONSOLE / PROCESS
; ------------------------------------------------------------------------------
ATTACH_PARENT_PROCESS       EQU 0FFFFFFFFh
STD_INPUT_HANDLE            EQU 0FFFFFFF6h
KEY_EVENT_ID                EQU 1           ; INPUT_RECORD.EventType for keyboard
VK_RETURN                   EQU 0Dh
ENTER_SCAN                  EQU 1Ch         ; hardware scan code for Enter
STD_OUTPUT_HANDLE           EQU 0FFFFFFF5h
STD_ERROR_HANDLE            EQU 0FFFFFFF4h
FILE_TYPE_CHAR              EQU 2

; ------------------------------------------------------------------------------
; RESOURCE IDs
; ------------------------------------------------------------------------------
IDI_ICON1                   EQU 101
IDI_SHIELD                  EQU 32518   ; MAKEINTRESOURCE(32518) — shell shield icon
IDR_DRIVER                  EQU 102
RT_RCDATA                   EQU 10
ICON_SIZE                   EQU 1078        ; base ICO bytes; CAB starts after

; ------------------------------------------------------------------------------
; FDI / CAB extraction
; ------------------------------------------------------------------------------
FDI_OUT_BUFSIZE             EQU 00100000h   ; 1 MB output buffer
SEEK_SET_VAL                EQU 0
SEEK_CUR_VAL                EQU 1
SEEK_END_VAL                EQU 2
fdintCOPY_FILE              EQU 2
fdintCLOSE_FILE_INFO        EQU 3

; ------------------------------------------------------------------------------
; PRIVILEGE
; ------------------------------------------------------------------------------
SE_PRIVILEGE_ENABLED        EQU 00000002h
TOKEN_ADJUST_PRIVILEGES     EQU 0020h
TOKEN_QUERY                 EQU 0008h
TOKEN_ADJUST_QUERY          EQU 0028h

; ------------------------------------------------------------------------------
; STRUCT DEFINITIONS
; ------------------------------------------------------------------------------

; MSG struct (x64 = 48 bytes)
MSG STRUCT
    hwnd        QWORD ?
    message     DWORD ?
    pad1        DWORD ?
    wParam      QWORD ?
    lParam      QWORD ?
    time        DWORD ?
    pt_x        DWORD ?
    pt_y        DWORD ?
    pad2        DWORD ?
MSG ENDS

; NMHDR (used in WM_NOTIFY)
NMHDR STRUCT
    hwndFrom    QWORD ?
    idFrom      QWORD ?
    nCode       DWORD ?
    nPad        DWORD ?
NMHDR ENDS

; NMITEMACTIVATE offsets (x64): NMHDR=24b + iItem + iSubItem
NMIA_iItem                  EQU 24
NMIA_iSubItem               EQU 28

; INITCOMMONCONTROLSEX
INITCOMMONCONTROLSEX STRUCT
    dwSize      DWORD ?
    dwICC       DWORD ?
INITCOMMONCONTROLSEX ENDS

; POINT
POINT STRUCT
    x           DWORD ?
    y           DWORD ?
POINT ENDS

; RECT
RECT STRUCT
    left        DWORD ?
    top         DWORD ?
    right       DWORD ?
    bottom      DWORD ?
RECT ENDS
