# VaultGuard

**Pure x64 MASM folder-protection for Windows — kernel minifilter, GUI + CLI, zero CRT, < 100 KB**

> 🔑 **Archive password:** `github.com` (required to extract `VaultGuard.7z`).  
> Password-protected to prevent antivirus false positives on kernel driver binaries.

> Reverse-engineered IOCTL layer communicating with `vg.sys`, a kernel FSFilter Content Screener
> signed by PROMOSOFT CORPORATION (2014), which loads on Windows 11 26H1 via the legacy
> cross-signed driver compatibility mechanism.

![VaultGuard main window](images/VaultGuard.jpg)

---

## Table of Contents

- [Origin](#origin)
- [Overview](#overview)
- [Architecture](#architecture)
- [Protection Flags](#protection-flags)
- [GUI Reference](#gui-reference)
- [CLI Reference](#cli-reference)
- [Service & Autostart](#service--autostart)
- [Use Cases](#use-cases)
- [Driver Communication](#driver-communication)
- [Registry Layout](#registry-layout)
- [Module Analysis](#module-analysis)
  - [handlers.asm — Commands, Notify & Status](#handlersasm--commands-notify--status)
  - [procpicker.asm — Running Process Picker](#procpickerasm--running-process-picker)
  - [impexp.asm — GUI Config Import/Export](#impexpasm--gui-config-importexport)
- [Building from Source](#building-from-source)
- [Regression Tests](#regression-tests)
- [Changelog](#changelog)
- [Known Limitations](#known-limitations)
- [Project Layout](#project-layout)
- [License](#license)

---

## Origin

This project started with a private message from **BetaTesta** on MyDigitalLife forums. He sent me the original *Secure Folders* binary — a Qt-based folder-protection suite — and asked whether I'd consider building something similar.

The binary turned out to be a real find. Inside it I found a kernel-mode FSFilter minifilter (`vg.sys`) signed in **March 2014** by **PROMOSOFT CORPORATION**. Microsoft's backward-compatibility policy loads cross-signed drivers timestamped before July 29, 2015 on Windows 10/11 without any WHQL or test-signing requirement. The driver just worked — on Windows 11 26H1, build 28000, without any patches or bypass tricks.

I reverse-engineered the IOCTL interface from the binary, extracted the driver, and rebuilt the entire userland from scratch in pure x64 MASM. During development I spent considerable time debugging driver interactions — tracing IOCTL responses, watching pool allocations, testing repeated load/unload cycles. Despite being 12 years old, `vg.sys` held up extremely well: no pool leaks, no dangling references, no stale device objects. The cleanup paths are correct. In the kernel world, that's not a given.

The result is VaultGuard — under 100 KB, zero CRT, the same binary as full Win32 GUI and fully scriptable CLI.

**Forum thread:** https://forums.mydigitallife.net/threads/vaultguard-%E2%80%94-folder-file-protection-in-pure-x64-assembly-60-kb-no-crt-win11-mica.90355/

Thanks to **BetaTesta** for the idea, the original binary, and the beta testing.

---

## Overview

Ground-up rewrite of a 12-year-old Qt/C++ folder-protection suite (~8 MB) in pure x64 MASM assembly.
The same binary runs as a full Win32 GUI application or a scriptable CLI tool.

| Property | Value |
|----------|-------|
| Binary size | < 100 KB |
| Original (Qt/C++) | ~8 MB — over 80× larger |
| CRT dependencies | Zero |
| Linked DLLs | `kernel32` `user32` `advapi32` `shell32` `ole32` `dwmapi` `gdi32` `comctl32` `uxtheme` `cabinet` |
| UI | Win32 — Dark Mode, Mica (DWM), PerMonitorV2 DPI, system tray |
| Driver | `vg.sys` — FSFilter Content Screener, Altitude 389991 |
| Driver service name | `clrcd` |
| VaultGuard service name | `VaultGuard` (optional, manual-start by default) |
| Registry | `HKCU\Software\VG\Paths` · `HKCU\Software\VG\Trusted` |
| Requires | Windows 11 x64, Administrator |
| Driver signature | Signed March 18, 2014 — loads via legacy cross-sign compatibility, no test-signing needed |

---

## Quick Start

Run from an **elevated command prompt** (Administrator). Driver installs itself on first run.

**GUI — double-click `vg.exe` or run without arguments:**

- Drag a folder or file from Explorer onto the **Protected Paths** panel → row appears instantly
- Drag a `.lnk` shortcut → resolved to real target automatically via `IShellLink`
- Drag an `.exe` file onto the **Trusted Apps** panel → executable name extracted and added as trusted process
- Click **Hidden / Locked / Read-only / No run** checkbox → flag applied to kernel driver immediately
- `Ctrl+Click` multiple rows → click **Remove selected** to delete them all at once
- Add a process name to **Allowed apps** → that process bypasses all driver protections
- `Shift+Minimize` → window hides to system tray
- Title bar shows live driver + protection state: `Driver: TRANSIENT | Protection: ON`

**CLI — same binary, scriptable:**

```
vg.exe /protection on
vg.exe /setitem "C:\Private" Locked
vg.exe /settrusted totalcmd64.exe Enabled
vg.exe /enumitems   out.csv
vg.exe /enumtrusted trust.csv
vg.exe /tray                        start minimized to system tray
vg.exe /autostart on                register Task Scheduler logon entry
vg.exe /service install             register app service as manual-start
vg.exe /driver install auto          install clrcd and set automatic driver start
vg.exe /uninstall                   stop and remove services, driver and config
vg.exe /?
```

Everything above — the GUI, the CLI, the COM `.lnk` resolver, the FDI driver extractor, the SCM installer, the IOCTL layer, the registry persistence, the Windows service runtime, the tray icon — is written in pure x64 MASM assembly. Zero CRT. Zero runtime. Every byte deliberate.

---

## Architecture

```mermaid
flowchart TD
    A[vg.exe launched] --> B{argc >= 2?}
    B -->|Yes| C[CliDispatch argv]
    B -->|No| D[CreateMainWindow GUI]
    C --> E{Known switch?}
    E -->|/service| SVC[_CliServiceInstall/Uninstall]
    E -->|/driver| DRV[_CliDriver clrcd lifecycle]
    E -->|/uninstall| UN[_CliFullUninstall cleanup]
    E -->|/autostart| AS[_CliAutostart schtasks.exe]
    E -->|/tray| TR[g_startMinimized=1 → GUI]
    E -->|/svcstart| SS[_SvcStart → StartServiceCtrlDispatcherW]
    E -->|other| F[CLI command handler]
    E -->|unknown| D
    D --> G[WM_CREATE: _OnCreate layout]
    G --> H[SetTimer 2000ms]
    H --> I[Message Loop]
    I --> J{WM_MESSAGE}
    J -->|WM_COMMAND| K[_OnCommand handlers.asm]
    J -->|WM_NOTIFY| L[_OnNotify flag checkboxes]
    J -->|WM_DROPFILES| M[_OnDropFiles drop.asm]
    J -->|WM_TIMER| N[UpdateStatusBar]
    J -->|WM_SIZE minimized+Shift| TY[_TrayAdd tray.asm]
    J -->|WM_TRAY| TM[_OnTrayMsg tray.asm]
    J -->|TaskbarCreated| TA[_TrayAdd re-register]
    J -->|WM_SETTINGCHANGE| O[_ReadDarkMode + ApplyDarkMode]
    K --> P[EnsureDriverReady]
    F --> P
    P --> Q{Device open?}
    Q -->|Yes| R[IOCTL DeviceIoControl]
    Q -->|No| S[InstallDriver: FDI extract + CreateServiceW]
    S --> T[StartDriver: SCM StartServiceW]
    T --> R
    R --> U[ConfigSave/Load: HKCU registry]
```

---

## Protection Flags

| Flag | CLI mode | Hex | Driver behavior |
|------|----------|-----|-----------------|
| Hidden | `Hidden` | `0x01` | Folder invisible — `STATUS_OBJECT_NAME_NOT_FOUND` + removed from dir listings |
| Locked | `Locked` | `0x02` | All access → `STATUS_ACCESS_DENIED` |
| Read-only | `Read-only` | `0x04` | Strips `FILE_WRITE_DATA` and `DELETE` from `DesiredAccess` |
| No execute | `No-execution` | `0x08` | Strips execute bits from `DesiredAccess` |
| Disabled | `Disabled` | `0x00` | Path stored in registry, inactive in driver |

Flags combine as a bitmask: `Hidden + Locked = 0x03`, `Hidden + Locked + Read-only = 0x07`, etc.

Overlapping path rules are cumulative in the driver. Their registry/UI order is not precedence: a disabled child cannot create an allow exception beneath a protected parent.

---

## GUI Reference

Launch `vg.exe` without arguments. Fixed **700 × 550 px** window.

### Main Window

Class `VGMainWnd`. Driver and protection state is embedded in the window title (refreshed every 2 seconds by `WM_TIMER`):

```
VaultGuard | Driver: STOPPED   | Protection: OFF
VaultGuard | Driver: TRANSIENT | Protection: ON
```

Dark Mode and Mica backdrop follow the system theme automatically via `WM_SETTINGCHANGE`.

### System Tray

- **`Shift+Minimize`** — hides window and adds tray icon
- **`/tray` switch** — starts directly as a tray-only process (hidden window)
- **Double-click tray icon** — restores main window
- **Right-click tray icon** — context menu (Restore / Exit)
- **`TaskbarCreated` message** — if Explorer restarts (crash or logon race), VaultGuard re-registers its tray icon automatically

> **UIPI note:** When launched elevated via Task Scheduler (`/rl highest`), `ChangeWindowMessageFilterEx` is called during `WM_CREATE` to allow the `TaskbarCreated` registered message (ID ≥ `0xC000`) to cross the integrity boundary from Medium-IL Explorer into the High-IL process. Without this, the tray icon would not appear after logon.

### Protected Folders Panel

| Control | Behavior |
|---------|----------|
| **[Add path...]** button | Opens `SHBrowseForFolderW` native folder browser |
| **[Remove selected]** button | Removes all selected entries (multi-select supported) |
| **Flag columns** (H / L / R / X) | Click any flag cell → toggles checkbox + sends IOCTL update to driver immediately |
| **Drag & Drop** | Accepts folders and files from Explorer; `.lnk` shortcuts resolved via COM `IShellLink`; `.exe` files dropped here add full path as protected item |

**Columns:**

| Column | Flag | Hex |
|--------|------|-----|
| Path | — | — |
| Hidden (H) | `VG_FLAG_HIDDEN` | `0x01` |
| Locked (L) | `VG_FLAG_LOCKED` | `0x02` |
| Read-only (R) | `VG_FLAG_READONLY` | `0x04` |
| No run (X) | `VG_FLAG_NOEXEC` | `0x08` |

### Trusted Processes Panel

Processes in this list bypass all driver protections — Hidden/Locked/Read-only rules do not apply to them.

Trust is global. The current driver does not expose an application-to-folder mapping, so a trusted process is trusted for every protected path.

| Control | Behavior |
|---------|----------|
| **Edit box** | Enter process executable name (e.g. `totalcmd64.exe`) |
| **[Add]** button | Strips path prefix (e.g. `C:\dir\app.exe` → `app.exe`), appends `.exe` if extension missing, lowercases → `IoctlAddTrusted` + `ConfigSaveTrusted` |
| **[Add running]** button | Opens "Select running process" dialog (procpicker.asm) — Ctrl/Shift multi-select — adds all selected processes at once |
| **[Remove]** button | Multi-select: `ConfigRemoveTrusted` per selected item → `IoctlRemoveTrusted(empty)` → `ConfigLoad` (reloads remaining) → `RefreshLists` |
| **[Export]** button | `GuiExportConfig` — opens Save dialog → writes `.vgc` file (UTF-16LE, `[Paths]`/`[Trusted]` sections) |
| **[Import]** button | `GuiImportConfig` — opens Open dialog → parses `.vgc` → `ConfigLoad` + `RefreshLists` |
| **Drag & Drop** | Drop an `.exe` file or `.lnk` shortcut onto this panel — executable name extracted and added directly as trusted process |

> **Note:** Removing sends an empty `IoctlRemoveTrusted` that wipes the **entire** active trusted list in the driver. `ConfigLoad` immediately reloads all remaining registry entries. The driver provides no per-item removal IOCTL.

---

## CLI Reference

Run from an **elevated command prompt** (Administrator):

```
vg.exe /?
vg.exe /protection    on | off
vg.exe /setitem       <path>   Hidden | Locked | Read-only | No-execution | Disabled
vg.exe /settrusted    <name>   Enabled | Disabled
vg.exe /enumitems     <out.csv>
vg.exe /enumtrusted   <out.csv>
vg.exe /tray
vg.exe /autostart     on | off
vg.exe /service       install | uninstall
vg.exe /driver        install [manual | auto]
vg.exe /driver        start | stop | manual | auto
vg.exe /driver        uninstall
vg.exe /uninstall
```

### Command Summary

| Command | Description | Example |
|---------|-------------|---------|
| `/?` `-h` `--help` | Print help to stdout | `vg.exe /?` |
| `/protection on\|off` | Enable or disable global protection | `vg.exe /protection on` |
| `/setitem <path> <mode>` | Set protection flags for a path | `vg.exe /setitem "C:\Data" Locked` |
| `/settrusted <name> <state>` | Add or remove a trusted process; full paths are reduced to a lowercase basename and `.exe` is appended when missing | `vg.exe /settrusted C:\Tools\CMD Enabled` |
| `/enumitems <file.csv>` | Export protected paths as UTF-16LE CSV | `vg.exe /enumitems out.csv` |
| `/enumtrusted <file.csv>` | Export trusted processes as UTF-16LE CSV | `vg.exe /enumtrusted trust.csv` |
| `/tray` | Start minimized to system tray | `vg.exe /tray` |
| `/autostart on\|off` | Register/remove Task Scheduler logon entry | `vg.exe /autostart on` |
| `/service install\|uninstall` | Register/remove VaultGuard Windows service | `vg.exe /service install` |
| `/driver install [manual\|auto]` | Install `clrcd` driver service; default start type is manual | `vg.exe /driver install auto` |
| `/driver start\|stop` | Start or stop the `clrcd` driver service | `vg.exe /driver start` |
| `/driver manual\|auto` | Change `clrcd` startup type via `ChangeServiceConfigW` | `vg.exe /driver auto` |
| `/driver uninstall` | Stop and remove `clrcd`; delete extracted `vg.sys` best-effort | `vg.exe /driver uninstall` |
| `/uninstall` | Full cleanup: disable protection, remove app service, remove driver service/file, delete HKCU config | `vg.exe /uninstall` |

### CSV Output Formats

`/enumitems` — UTF-16LE with BOM:
```
Path,Hidden,Locked,ReadOnly,NoExec
C:\Private,0,1,0,0
```

`/enumtrusted` — UTF-16LE with BOM:
```
Application
totalcmd64.exe
```

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Unknown switch / bad argument / driver error |

---

## Service & Autostart

### Windows Service (`/service install`)

```
vg.exe /service install
vg.exe /service uninstall
```

Registers `vg.exe` itself as a Windows service named **`VaultGuard`**:

- **Start type:** `SERVICE_DEMAND_START` — manual start (immediately started after creation via `StartServiceW`)
- **Binary path:** `"<full path to vg.exe>" /svcstart`
- On install: service is created **and immediately started** via `StartServiceW`
- On uninstall: service is stopped (if running) and deleted via `DeleteService`

The internal `/svcstart` switch is dispatched by `CliDispatch` → `_SvcStart` → `StartServiceCtrlDispatcherW`. The SCM thread runs the standard Win32 service lifecycle:

```
_SvcMain → RegisterServiceCtrlHandlerExW → SetServiceStatus(RUNNING)
         → WaitForSingleObject(stop_event, INFINITE)
         → on STOP/SHUTDOWN/PRESHUTDOWN: SetEvent → SetServiceStatus(STOPPED)
```

Accepted controls: `SERVICE_CONTROL_STOP`, `SERVICE_CONTROL_SHUTDOWN`, `SERVICE_CONTROL_PRESHUTDOWN`.

> The service mode runs the full GUI (window + message loop) — the same binary, no separate service-only build. The SCM thread acts as a watchdog; the main thread runs the normal Win32 message loop.

### Driver Service (`/driver ...`)

```
vg.exe /driver install
vg.exe /driver install auto
vg.exe /driver manual
vg.exe /driver auto
vg.exe /driver start
vg.exe /driver stop
vg.exe /driver uninstall
```

Manages the real protection service, **`clrcd`**, through WinAPI/SCM calls only:

- `install` extracts `vg.sys`, creates the kernel driver service and leaves it `SERVICE_DEMAND_START` by default
- `install auto` creates the service and changes start type to `SERVICE_AUTO_START`
- `manual` / `auto` call `ChangeServiceConfigW` for the existing `clrcd` service
- `start` / `stop` call `StartServiceW` / `ControlService`
- `uninstall` stops and deletes `clrcd`, then deletes `%SystemRoot%\System32\drivers\vg.sys` best-effort

### Full Uninstall (`/uninstall`)

```
vg.exe /uninstall
```

Disables live protection if the device is open, removes the optional `VaultGuard` app service, stops/deletes `clrcd`, deletes the extracted driver file best-effort, and removes `HKCU\Software\VG`.

### Logon Autostart (`/autostart on`)

```
vg.exe /autostart on
vg.exe /autostart off
```

Registers a **Task Scheduler** logon task:

```
schtasks.exe /create /f /sc onlogon /rl highest /tn VaultGuard
             /tr "\"<exe>\" /tray"
```

Key properties:
- `/rl highest` — runs elevated (High Integrity Level) without UAC prompt at logon
- `/sc onlogon` — fires once per user logon session
- `/tray` — launches directly to system tray (no window flash)
- Battery restrictions cleared after creation: `DisallowStartIfOnBatteries:$false`, `StopIfGoingOnBatteries:$false`

> This is the only officially supported Microsoft method for silent elevated autostart on Windows 10/11. `HKCU\Run` entries are silently skipped by Windows for processes with `requireAdministrator` manifest.

---

## Use Cases

### Lock a folder, allow one trusted process

```powershell
vg.exe /protection on
vg.exe /setitem "C:\Private" Locked

# Allow Total Commander through
vg.exe /settrusted totalcmd64.exe Enabled

# Verify
vg.exe /enumitems   items.csv
vg.exe /enumtrusted trust.csv

# Revoke when done
vg.exe /settrusted totalcmd64.exe Disabled
```

### Hide a folder from Explorer

```powershell
vg.exe /setitem "C:\Secret" Hidden
```

The folder disappears from Explorer, `dir`, and all directory enumeration APIs. Processes that know the full path can still address it — combine with `Locked` to block those too (use the GUI checkboxes to set multiple flags per path).

### Read-only archive

```powershell
vg.exe /setitem "C:\Backups" Read-only
```

The driver strips `FILE_WRITE_DATA` and `DELETE` bits at the kernel level. Trusted processes can still write normally.

### Set up persistent elevated autostart

```powershell
vg.exe /autostart on
# Task Scheduler entry created. VaultGuard starts at logon to tray, elevated, no UAC prompt.

# To remove:
vg.exe /autostart off
```

### Install as a Windows service (manual start)

```powershell
vg.exe /service install
# Service VaultGuard created (DEMAND_START) and immediately started.

# To remove:
vg.exe /service uninstall
```

### Scripted status check

```powershell
vg.exe /enumitems C:\temp\items.csv
$rows   = Import-Csv C:\temp\items.csv -Encoding Unicode
$locked = $rows | Where-Object { $_.Locked -eq '1' }
Write-Host "Locked paths: $($locked.Count)"
```

`Import-Csv -Encoding Unicode` reads UTF-16LE correctly on both Windows PowerShell 5.1 and PowerShell 7.

---

## Driver Communication

```mermaid
flowchart TD
    UA[User action: GUI or CLI] --> EDR[EnsureDriverReady]
    EDR --> OD[OpenDevice: \\.\BE79F7D8...]
    OD -->|success| IOCTL
    OD -->|fail| ID[InstallDriver: FDI extract + CreateServiceW]
    ID --> SD[StartDriver: SCM StartServiceW]
    SD --> OD2[OpenDevice retry]
    OD2 --> IOCTL
    IOCTL --> IAP[IoctlAddPath flags + NT path]
    IAP --> QDD[QueryDosDeviceW C: → Device/HarddiskVolumeN]
    QDD --> DIO[DeviceIoControl 0x9C402400, packed buffer >= 0x6414 bytes]
    DIO --> CSP[ConfigSavePath: HKCU/Software/VG/Paths/path = REG_DWORD flags]
    CSP --> HIDE[Folder disappears from Explorer / returns ACCESS_DENIED]

    RT[Remove trusted: GUI or CLI] --> IRT[IoctlRemoveTrusted empty input clears ALL]
    IRT --> CRT[ConfigRemoveTrusted: delete registry entry]
    CRT --> CL[ConfigLoad: reload remaining entries from registry into driver]
```

Reverse-engineered IOCTL codes for `vg.sys`:

| IOCTL | Code | Notes |
|-------|------|-------|
| `IOCTL_VG_ADD_PATH` | `0x9C402400` | Replaces the complete path list; record size `0x1404`; original five-record input is `0x6414` bytes |
| `IOCTL_VG_ENUM_PATHS` | `0x9C402404` | |
| `IOCTL_VG_ADD_TRUSTED` | `0x9C402408` | Replaces the complete trusted list; record size `0xD94`, process name at `+4` |
| `IOCTL_VG_REMOVE_TRUSTED` | `0x9C402408` | empty input (`size=0`) clears entire list |
| `IOCTL_VG_ENUM_TRUSTED` | `0x9C40240C` | |
| `IOCTL_VG_SET_ACTIVE` | `0x9C40241C` | DWORD (4 bytes) |
| `IOCTL_VG_GET_STATUS` | `0x9C402420` | 16-byte `VG_STATUS` struct |
| `IOCTL_VG_CLEAR_ALL` | `0x9C402424` | Undocumented reset operation; not used for normal list synchronization |

Device path: `\\.\BE79F7D853E643089D51EDCDA79805C4`

`vg.sys` is embedded inside `vg.exe` as a resource — an LZX CAB appended after the first 1078 bytes of an ICO file header, extracted at install time via FDI (`cabinet.lib`, no temp files on disk during extraction).

---

## Registry Layout

```
HKEY_CURRENT_USER\Software\VG\
├── Paths\
│   "C:\Private\Data"   REG_DWORD  0x00000002  (Locked)
│   "C:\Secret"         REG_DWORD  0x00000001  (Hidden)
│   "C:\Temp\Archive"   REG_DWORD  0x00000000  (Disabled)
└── Trusted\
    "totalcmd64.exe"    REG_DWORD  0x00000001
    "explorer.exe"      REG_DWORD  0x00000001
```

`ConfigLoad` enumerates both keys, packs all active records, and submits each complete list in one IOCTL. The SET-style IOCTLs replace their list rather than appending one record. For an empty path list it sends a syntactically valid system-drive record with `flags=0`; a completely zero-filled input is accepted by the driver but does not reliably remove its final in-memory path.
The driver holds no persistent state across reboots.

---

## Module Analysis

19 MASM source files, each with a single defined responsibility.

### `main.asm` — Entry Point & Globals

Entry point: `mainCRTStartup`

Startup sequence:
1. `GetStdHandle(STD_OUTPUT_HANDLE)` + `GetFileType` → `AttachConsole(-1)` if no TTY
2. `GetCommandLineW` → `CommandLineToArgvW` → `lea rdx, [rsp+20h]` as `&argc`
3. `argc >= 2` → `CliDispatch(argv[1], argv, argc)`; returns 0 (unknown) or `argc < 2` → start GUI

Public globals:

| Symbol | Type | Description |
|--------|------|-------------|
| `g_hInstance` | `dq` | Process HINSTANCE |
| `g_hwndMain` | `dq` | Main window handle |
| `g_hwndLvPaths` | `dq` | ListView "Protected Paths" |
| `g_hwndLvTrusted` | `dq` | ListView "Trusted Processes" |
| `g_hwndBtnToggle` | `dq` | Toggle button |
| `g_hDevice` | `dq` | Handle to `\\.\BE79F7D853E643089D51EDCDA79805C4` |
| `g_hFontMain`, `g_hFontSmall` | `dq` | GDI font handles |
| `g_hBrushBg` | `dq` | Background brush (`0x202020` in dark mode) |
| `g_isDarkMode` | `dd` | 1 = dark mode active |
| `g_startMinimized` | `dd` | 1 = start hidden to tray (`/tray` switch) |
| `g_driverInstalled`, `g_driverRunning`, `g_protActive` | `dd` | Driver state flags |
| `g_ioBuf` | `65536 B` | IOCTL enumeration buffer (64 KB) |
| `g_pathBuf`, `g_tempBuf`, `g_statusBuf` | `520 W` | Wide-character scratch buffers |

---

### `window.asm` — Window Skeleton

Contains exclusively `MainWndProc` and `CreateMainWindow`. Fixed size **700 × 550 px**, class `VGMainWnd`.

On creation, calls `RegisterWindowMessageW("TaskbarCreated")` and stores the dynamic message ID in `g_wmTaskbarCreated` — used both in `MainWndProc` and to unlock the UIPI filter in `_OnCreate`.

| Message | Action |
|---------|--------|
| `WM_CREATE` | `_OnCreate` (layout.asm) |
| `WM_DESTROY` | `KillTimer`, `DeleteObject` (fonts + brush), `PostQuitMessage(0)` |
| `WM_CLOSE` | `DestroyWindow` |
| `WM_SIZE` (minimized + Shift held) | `_TrayAdd` — hide to system tray |
| `WM_TRAY` | `_OnTrayMsg` — handle tray icon mouse events |
| `WM_DROPFILES` | `_OnDropFiles` (drop.asm) |
| `WM_NOTIFY` | `_OnNotify` (handlers.asm) — flag checkboxes in the ListView |
| `WM_COMMAND` | `_OnCommand` (handlers.asm) — button clicks |
| `WM_TIMER` | `UpdateStatusBar` every 2 seconds |
| `WM_SETTINGCHANGE` | `_ReadDarkMode` + `ApplyDarkMode` + `_ApplyThemeColors` + `InvalidateRect` |
| `WM_ERASEBKGND` | `FillRect(g_hBrushBg)` — paints client area with theme background |
| `WM_CTLCOLORSTATIC` | Dark mode: `SetBkMode(OPAQUE)` + colors + returns `g_hBrushBg` |
| `TaskbarCreated` | `_TrayAdd` — re-registers tray icon after Explorer restart |

---

### `layout.asm` — Control Creation

`_OnCreate(rcx=hwnd)` creates all widgets in a single pass:

```
[y=  8] Toggle button (x=182)
[y=  8] [Add path...]  (x=364)  +  [Remove selected]  (x=504)
[y= 10] "Protected files/folders" header (x=20)
[y= 40] ListView Paths (w=624, h=220): columns Path/H/L/R/X
         LVS_REPORT|LVS_SHOWSELALWAYS — multi-select, row checkboxes
[y=278] "Allowed apps (trusted)" header (x=20)
[y=276] Trusted edit box (x=182)  +  [Add] (x=364)  +  [Add running] (x=440)  +  [Remove] (x=556)
[y=308] ListView Trusted (w=624, h=140, ~6 rows): 1 column Process name — multi-select
[y=454] [Export] (x=20)  +  [Import] (x=115)
[y=482] Author/copyright static label (x=20, w=624, centered)
```

Key calls: `InitCommonControlsEx(ICC_LISTVIEW_CLASSES)`, `DragAcceptFiles(TRUE)`, `ChangeWindowMessageFilterEx` for `WM_DROPFILES` / `WM_COPYDATA` / `WM_COPYGLOBALDATA` / `TaskbarCreated` (all MSGFLT_ALLOW — required for High-IL process to receive drops and shell messages from Medium-IL Explorer), `SetTimer(TIMER_STATUS_ID, 2000)`.

---

### `tray.asm` — System Tray

| Procedure | Description |
|-----------|-------------|
| `_TrayAdd(rcx=hwnd)` | `Shell_NotifyIconW(NIM_ADD)` with icon handle and tooltip `"VaultGuard"` |
| `_TrayRemove(rcx=hwnd)` | `Shell_NotifyIconW(NIM_DELETE)` |
| `_OnTrayMsg(rcx=hwnd, rdx=lParam)` | `WM_LBUTTONDBLCLK` → `ShowWindow(SW_RESTORE)` + `SetForegroundWindow`; right-click → context menu (Restore / Exit) |

`WM_TRAY` is a user-defined message (`WM_APP + 1`). `_TrayAdd` sets `uCallbackMessage = WM_TRAY` so all tray icon mouse events are routed to `MainWndProc`.

---

### `theme.asm` — Dark Mode & Colors

| Procedure | Description |
|-----------|-------------|
| `_ReadDarkMode` | Reads `AppsUseLightTheme` registry value; sets `g_isDarkMode` |
| `ApplyDarkMode(rcx=hwnd)` | `DwmSetWindowAttribute(DWMWA_USE_IMMERSIVE_DARK_MODE)` + Mica via `DWMSBT_MAINWINDOW` |
| `_SetLvColors` | `SetWindowTheme("DarkMode_Explorer")` + ListView color messages |
| `_ApplyThemeColors` | Recreates `g_hBrushBg`; calls `_SetLvColors` for both ListViews |

---

### `handlers.asm` — Commands, Notify & Status

**`_OnCommand`** dispatch by control ID:

| IDC | Action |
|-----|--------|
| `IDC_BTN_TOGGLE` | `IoctlSetActive(!g_protActive)` |
| `IDC_BTN_ADD_PATH` | `SHBrowseForFolderW` → stage as `g_pendingPath` → `RefreshLists` |
| `IDC_BTN_REM_PATH` | Multi-select loop: `LVM_GETNEXTITEM(-1, LVNI_SELECTED)` → `IoctlAddPath(0)` + `ConfigRemovePath` + `LVM_DELETEITEM`; repeat until no more selected |
| `IDC_BTN_ADD_TRUSTED` | Strip path prefix, append `.exe` if missing, lowercase → `IoctlAddTrusted` + `ConfigSaveTrusted` |
| `IDC_BTN_ADD_RUNNING` | `ShowProcPicker(hwnd)` → on return > 0: `RefreshLists` |
| `IDC_BTN_REM_TRUSTED` | Multi-select loop → `ConfigRemoveTrusted` per item; `IoctlRemoveTrusted(empty)` + `ConfigLoad` + `RefreshLists` |
| `IDC_BTN_EXPORT` | `GuiExportConfig(hwnd)` — writes `.vgc` via `GetSaveFileNameW` |
| `IDC_BTN_IMPORT` | `GuiImportConfig(hwnd)` + `ConfigLoad` + `RefreshLists` |

**`_OnNotify`** — NM_CLICK on Protected Paths ListView: col 1–4 → toggle flag bit → `IoctlAddPath` + `ConfigSavePath` + `RefreshLists`.

**`UpdateStatusBar`** — `EnsureDriverReady` → `IoctlGetStatus` → updates title bar and toggle button text. Repaint suppressed when state has not changed.

**`RefreshLists`** — `IoctlEnumPaths` + `IoctlEnumTrusted` → `LVM_DELETEALLITEMS` → `_LvInsertItem` for each entry.

---

### `procpicker.asm` — Running Process Picker

`ShowProcPicker(rcx=hwndOwner)` → `eax = count of processes added`

Opens a modal dialog snapped flush against the right edge of the main window.

| Feature | Description |
|---------|-------------|
| **Process list** | Snapshot via `CreateToolhelp32Snapshot` + `Process32FirstW/NextW`; system processes filtered |
| **Multi-select** | Ctrl+Click / range select; all selected entries submitted at once |
| **Submit** | `[OK]` / double-click: `EnsureDriverReady` → `wcs_ascii_lower_inplace` → `IoctlAddTrusted` + `ConfigSaveTrusted` per item → `EndDialog(count)` |
| **Dark mode** | Full dark: `WM_ERASEBKGND` + `WM_CTLCOLORSTATIC/BTN` handlers + `_SetLvColors` for ListView |
| **Positioning** | `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS=9)` on both windows; compensates for invisible DWM shadow border to place dialog flush-right of main window at pixel precision |

---

### `impexp.asm` — GUI Config Import/Export

| Procedure | Description |
|-----------|-------------|
| `GuiExportConfig(rcx=hwndOwner)` | `GetSaveFileNameW` (filter `*.vgc`) → creates file → writes UTF-16LE BOM + `[Paths]` section (path`=`decimal flags) + `[Trusted]` section (name`=1`) → confirmation `MessageBoxW` |
| `GuiImportConfig(rcx=hwndOwner)` | `GetOpenFileNameW` → reads `.vgc` file → parses `[Paths]`/`[Trusted]` sections → `RegSetValueExW` per entry; caller calls `ConfigLoad` + `RefreshLists` afterward |

File format (`.vgc`, UTF-16LE with BOM):
```
[Paths]
C:\Private=2
C:\Secret=1
[Trusted]
totalcmd64.exe=1
```

---

### `drop.asm` — Drag & Drop

**`_OnDropFiles(rcx=HDROP, rdx=hMainWnd)`:**

1. `DragQueryFileW(0)` → first dropped path into `g_pathBuf`
2. Detects drop target: if cursor Y-position is over the Trusted panel → route to trusted add path
3. Last 4 chars are `.lnk` (via `wcscmp_ci`) → call `ResolveLnkPath` → `GetLongPathNameW` (canonical case)
4. **Trusted panel drop:** extracts filename component from path → lowercase → `IoctlAddTrusted` + `ConfigSaveTrusted`
5. **Paths panel drop:** auto-commits any prior `g_pendingPath` to registry via `ConfigSavePath(flags=0)` before overwriting; stores resolved path in `g_pendingPath` → `RefreshLists`
6. `DragFinish`

**`ResolveLnkPath(rcx=.lnk path, rdx=out buf)`:**

`CoInitialize` → `CoCreateInstance(CLSID_ShellLink)` → `QueryInterface(IID_IPersistFile)` → `IPersistFile::Load` → `IShellLinkW::GetPath` → full COM release chain → `CoUninitialize`

---

### `service.asm` — Windows Service Runtime

| Procedure | Description |
|-----------|-------------|
| `_CliServiceInstall` | Opens SCM → `CreateServiceW` (name=`VaultGuard`, `DEMAND_START`, binary=`"<exe>" /svcstart`) → `StartServiceW` |
| `_CliServiceUninstall` | Opens SCM → `OpenServiceW` → `ControlService(STOP)` → `DeleteService` |
| `_SvcStart` | Builds `SERVICE_TABLE_ENTRYW[2]` on stack → `StartServiceCtrlDispatcherW` → `ExitProcess(0)` |
| `_SvcMain` | `CreateEventW(manual-reset)` → `RegisterServiceCtrlHandlerExW` → `SetServiceStatus(RUNNING, accepts=STOP\|SHUTDOWN\|PRESHUTDOWN)` → `WaitForSingleObject(INFINITE)` → `SetServiceStatus(STOPPED)` |
| `_SvcCtrlHandler` | `STOP/SHUTDOWN/PRESHUTDOWN` → `SetServiceStatus(STOP_PENDING)` → `SetEvent(stop_event)` |

`SERVICE_ACCEPT_PRESHUTDOWN` (`0x100`) is registered via `RegisterServiceCtrlHandlerExW` (the extended variant) to receive clean shutdown notification before system-level services stop.

---

### Driver Layer — SCM, Device, IOCTL

| Property | Value |
|----------|-------|
| Service name | `clrcd` |
| Display name | `Vault Guard Driver` |
| Type | `SERVICE_KERNEL_DRIVER` |
| Start | `SERVICE_DEMAND_START` |
| Dependency | `FltMgr\0\0` |
| Device path | `\\.\BE79F7D853E643089D51EDCDA79805C4` |

| Procedure | Description |
|-----------|-------------|
| `driver_scm.asm` | `InstallDriver`, `StartDriver`, `StopDriver`, `UninstallDriver`, `SetDriverStartType`, `DeleteDriverFile` |
| `device.asm` | `OpenDevice`, `CloseDevice`, `EnsureDriverReady` |
| `ioctl.asm` | `IoctlSetActive`, path/trusted add-remove, enum, status, clear-all wrappers |
| `driver_consts.inc` | Shared driver-layer symbol declarations (`clrcd`, device path, status/drive buffers) |

---

### `config.asm` — Registry Persistence

| Procedure | Description |
|-----------|-------------|
| `ConfigLoad` | Enumerates both registry keys, packs every active path/trusted record, then submits one complete buffer per list; uses a valid `flags=0` sentinel for an empty path list |
| `ConfigSavePath(rcx=path, rdx=flags)` | `RegCreateKeyExW` → `RegSetValueExW(path, flags)` |
| `ConfigRemovePath(rcx=path)` | `RegOpenKeyExW` → `RegDeleteValueW` |
| `ConfigSaveTrusted(rcx=name_lowercase)` | `RegCreateKeyExW` → `RegSetValueExW(name, 1)` |
| `ConfigRemoveTrusted(rcx=name)` | `RegOpenKeyExW` → `RegDeleteValueW` |
| `ConfigDeleteAll` | Deletes `Paths`, `Trusted`, then `HKCU\Software\VG` via `RegDeleteKeyW` |

---

### `cli.asm` — Command-Line Interface

Switch comparison uses `wcscmp_ci` — fast ASCII case-insensitive wide-string compare, no `CharLowerW`. All switches work regardless of capitalization.

Every exit path goes through `_CliFinish(code)` → `ConsoleSendEnter()` (injects `VK_RETURN` via `WriteConsoleInputW`) so CMD prompt reappears immediately without waiting for Enter.

**Switch dispatch order:** `/?` → `/service` → `/driver` → `/uninstall` → `/enumitems` → `/enumtrusted` → `/protection` → `/setitem` → `/settrusted` → `/svcstart` → `/tray` → `/autostart` → unknown (return 0 → GUI mode)

---

### `export.asm` — CSV Export

Owns all enumeration and file-writing logic for `/enumitems` and `/enumtrusted`.

| Procedure | Description |
|-----------|-------------|
| `_CliEnumItems(rcx=outfile)` | Opens file → writes UTF-16LE BOM + CSV header → enumerates `HKCU\Software\VG\Paths` → writes path + 4 flag columns per row → closes file → `ExitProcess(0)` |
| `_CliEnumTrusted(rcx=outfile)` | `IoctlEnumTrusted` (verifies driver ready) → opens file → writes UTF-16LE BOM + header → enumerates `HKCU\Software\VG\Trusted` → writes one name per row → `ExitProcess(0)` |
| `_WriteBytes` (private) | `WriteFile` wrapper |
| `_WriteWStr` (private) | Wide string → `wcslen_p` → `_WriteBytes` |

CSV is written from the registry (authoritative persisted state) rather than the driver's enumeration buffer, which can lag after flag-change operations.

---

### `res.asm` — Driver Extraction (FDI)

The driver `vg.sys` is embedded inside `vg.exe` as a resource: an LZX CAB appended to the ICO file header.

1. `FindResourceW(NULL, IDR_DRIVER=102, RT_RCDATA=10)` → resource pointer
2. `LockResource` → raw bytes; CAB starts at offset **1078 bytes**
3. All FDI callbacks operate in memory — no temp files on disk
4. `FDICopy` → heap buffer → `WriteFile` to `%SystemRoot%\system32\drivers\vg.sys`

CAB is packed at ~42% of original size via LZX compression.

---

### `strutil.asm` — String Utilities

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `wcslen_p` | `rcx=s → rax=count` | Wide strlen |
| `wcscpy_p` | `rcx=dst, rdx=src → rax=dst` | Wide strcpy |
| `wcscat_p` | `rcx=dst, rdx=src → rax=dst` | Wide strcat |
| `wcscmp_ci` | `rcx=a, rdx=b → rax=0/nonzero` | Case-insensitive wide compare (ASCII A-Z only) |
| `wcs_ascii_lower_inplace` | `rcx=s` | Lowercases A-Z in place |
| `IntToDecW` | `rcx=val, rdx=buf → rax=ptr` | DWORD → wide decimal string |
| `IntToHexW` | `rcx=val, rdx=buf → rax=ptr` | DWORD → 8-char wide hex string |
| `WideWriteConsole` | `rcx=handle, rdx=str` | `WriteConsoleW`; falls back to ANSI `WriteFile` if handle is not a console |
| `WideWriteLn` | `rcx=str` | `WideWriteConsole(stdout, str)` + CRLF |
| `ConsoleSendEnter` | — | Injects `VK_RETURN` via `WriteConsoleInputW` |

---

### `listview.asm` — ListView Wrappers

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `_LvAddColumn` | `rcx=hwnd, rdx=idx, r8=width, r9=text` | `LVM_INSERTCOLUMNW` |
| `_LvInsertItem` | `rcx=hwnd, rdx=row, r8=col, r9=text` | `LVM_INSERTITEMW` / `LVM_SETITEMW` |
| `_LvGetItemText` | `rcx=hwnd, rdx=row, r8=col, r9=buf` | `LVM_GETITEMTEXTW` |

---

## Building from Source

Requires Visual Studio with MASM x64 toolchain (auto-detected via `vswhere.exe`):

```powershell
.\build.ps1          # full build — steps 0 through 4
.\build.ps1 -SkipRC  # skip step 0 (icon packaging) and step 1 (rc.exe)
```

Build steps:
```
[0] makecab IcoBuilder\vg.sys → LZX CAB → prepend 1078 B ICO header → ICON\vg.ico
[1] rc.exe /c65001 vg.rc → vg.res
[2] ml64.exe /c /Cp /Cx /Zi
    (strutil res driver_scm device ioctl config cli export service theme listview handlers drop tray layout procpicker impexp window main)
[3] link.exe /SUBSYSTEM:WINDOWS /NODEFAULTLIB /MANIFEST:EMBED /MANIFESTUAC:requireAdministrator
    Libs: kernel32 user32 advapi32 shell32 ole32 dwmapi gdi32 comctl32 uxtheme cabinet
[4] dumpbin — verify: no CRT imports, allowed DLL set only
```

Intermediates (`*.obj`, `*.res`, `*.pdb`) are deleted on completion.

---

## Regression Tests

`tests/cli_test.ps1` — **84 regression checks**, CLI interface only, no GUI required.  
Requires `bin\vg.exe`, Administrator context, and an isolated NTFS test volume. The script installs/starts/removes `clrcd` as needed and performs a full uninstall check.

```powershell
powershell -ExecutionPolicy Bypass -File tests\cli_test.ps1 -TestDrive X:
# -KeepOutput   preserves CSV output files in tests\out\
```

Never point `-TestDrive` at a system/data volume: the suite deliberately applies protection to the volume root. A temporary NTFS VHD mounted as `X:` is the recommended target.

| Group | Tests | What is verified |
|-------|-------|-----------------|
| Help | 6 | `/?` output and command list |
| Driver lifecycle | 14 | install/start/stop/uninstall and Manual/Auto start modes |
| setitem flags | 4 | Each flag individually → registry value |
| setitem Disabled/overwrite | 4 | Inactive value 0 and last-mode-wins persistence |
| enumitems CSV | 7 | File content, rows, flag bits, disabled entries |
| settrusted + enumtrusted | 12 | Registry/CSV and remove-one-keeps-other behavior |
| protection/error cases | 6 | on/off and invalid argument exit codes |
| Test-volume round trip | 13 | Root/subfolder flags and CSV on the selected volume |
| Driver enforcement | 14 | Read-only/Locked behavior and lifting protection |
| Full uninstall | 4 | Services, driver, and registry are removed |

`tests/rule_collision_test.ps1 -TestDrive X:` adds **55 enforcement checks** covering the last-rule transition, seven simultaneous paths, six trusted names, reversed update order, same-basename executables, an executable that is both protected and trusted, parent/child collisions, `No-execution`, global on/off, and driver restart persistence.

`tests/gui_sync_test.ps1` drives the native window controls and verifies the complete-list synchronization regression: disabling one path keeps the other path active, disabling one trusted process keeps the other trusted process active, and adding a third process preserves the existing entry. It requires an empty `HKCU\Software\VG` configuration and a stopped `clrcd`; test-owned state is removed afterward.

`tests/driver_protocol_probe.ps1` is the destructive driver-level protocol probe used to confirm SET/replace semantics, the valid zero-flags empty-list transition, overlapping-path behavior, trusted-record layout, and global trust. It refuses to run while `clrcd` is already active.

All tests capture output via `Start-Process -RedirectStandardOutput`, which exercises the `WriteConsoleW → WriteFile ANSI fallback` path in `WideWriteConsole`.

---

## Changelog

<details open>
<summary><strong>07.11.2026 — v1.04: 128 KB buffer expansion, active capacity guard, window title bar v1.04</strong></summary>

### 128 KB IOCTL buffer upgrade (`VG_IOCTL_BUF_SIZE EQU 131072`)
- **Trusted processes**: capacity expanded from 18 to **37** active processes.
- **Protected paths**: capacity expanded from 12 to **25** active folder paths.
- The `g_ioBuf` allocation resides in `.data?` (uninitialized BSS), keeping `vg.exe` under 75 KB on disk with zero CRT runtime.

### Zero-silent-drop gatekeeper (`ConfigTrustedCanAdd`)
- Eliminates silent drop behavior when exceeding the driver's IOCTL buffer capacity.
- Intercepts all four process-entry and activation vectors:
  1. Direct entry via text box (`IDC_BTN_ADD_TRUSTED`).
  2. Running process picker multi-selection loop (`procpicker.asm`).
  3. Shell drag-and-drop (`drop.asm`).
  4. ListView row checkbox re-activation (`LVN_ITEMCHANGED` in `handlers.asm`), with automatic rollback to unchecked state upon rejection.
- Displays a native warning dialog (`MessageBoxW`) and rejects registry persistence, ensuring the UI and kernel driver remain 100% synchronized.
- Smart idempotency check: re-adding an already active process does not consume additional capacity.

### UI & version metadata
- Title bar updated with live version tag: `VaultGuard v1.04 | Driver: <STATE> | Protection: <STATE>`.
- PE resource version bumped to `FILEVERSION 1,0,0,4` / `ProductVersion 1.04`.
- Application manifest synchronized to `version="1.0.0.4"`.
- Build system (`build.ps1`) automatically ensures the `ICON\` output directory exists for CAB packaging on fresh checkouts.

</details>

<details>
<summary><strong>07.08.2026 — v1.03: Windows service, system tray, Task Scheduler autostart, export split, UIPI fix</strong></summary>

- Background service integration with manual-start default.
- System tray minimization via `Shift+Minimize` and `/tray` CLI switch.
- Auto-reconnect on Explorer restart (`TaskbarCreated`).
- Task Scheduler elevated logon autostart (`/autostart on`).
- Config export and import (`.vgc`).

</details>

---

## Known Limitations

| Item | Status |
|------|--------|
| `wcscmp_ci` | ASCII only (A-Z). Paths with non-ASCII characters use case-sensitive comparison — sufficient for NT paths and CLI switches |
| COM apartment | `CoInitialize`/`CoUninitialize` at every `.lnk` resolution; safe for GUI usage |
| Password mode | `/p` is parsed and silently ignored; driver has no password enforcement |
| Light mode | GUI works in light mode; ListView colors fall back to system defaults |
| Trusted list removal | No per-item IOCTL — driver only supports clearing the entire list, requiring a full reload cycle |
| Scoped trust | Trusted executable basenames are global; every copy with the same filename is trusted for every protected path, and the driver cannot bind an application to selected folders |
| Protected trusted executable | A trusted executable stored inside a Locked/No-execution path cannot bootstrap itself because the untrusted launcher must open the image first; after its own path is accessible, its process-name trust applies normally |
| Nested exceptions | Path rules are cumulative; a disabled child does not override protection inherited from a matching parent |
| Multi-file drop | Only the first dropped file/folder is processed per `WM_DROPFILES`; multi-file drops discard all but the first |
| Service + GUI | In service mode the full GUI is active; no headless/service-only mode |

---

## Project Layout

```
VaultGuard/
├── x64/
│   ├── consts.inc      IOCTL codes, flags, struct offsets, control IDs
│   ├── globals.inc     EXTRN declarations
│   ├── main.asm        Entry point, globals, message loop
│   ├── window.asm      MainWndProc + CreateMainWindow
│   ├── layout.asm      _OnCreate — all controls, UIPI message filters
│   ├── theme.asm       Dark mode, Mica, ListView colors
│   ├── handlers.asm    _OnCommand, _OnNotify, UpdateStatusBar, RefreshLists
│   ├── procpicker.asm  ShowProcPicker — running process picker dialog
│   ├── impexp.asm      GuiExportConfig, GuiImportConfig — .vgc file import/export
│   ├── drop.asm        WM_DROPFILES + ResolveLnkPath (IShellLink COM) + trusted panel routing
│   ├── tray.asm        System tray: _TrayAdd, _TrayRemove, _OnTrayMsg
│   ├── listview.asm    ListView wrappers
│   ├── driver_scm.asm  clrcd SCM lifecycle + driver file cleanup
│   ├── device.asm      Device open/close + EnsureDriverReady
│   ├── ioctl.asm       DeviceIoControl wrappers + path marshalling
│   ├── driver_consts.inc shared driver-layer declarations
│   ├── config.asm      ConfigLoad/Save/Remove/DeleteAll (registry)
│   ├── cli.asm         CliDispatch — CLI interface + RunCmdAndWait + _CliAutostart
│   ├── export.asm      _CliEnumItems, _CliEnumTrusted — CSV export
│   ├── service.asm     Windows service runtime — _SvcStart, _SvcMain, _SvcCtrlHandler
│   ├── strutil.asm     String utilities + WideWriteLn/WideWriteConsole
│   ├── res.asm         ExtractDriver — FDI decompression of CAB from icon
│   ├── vg.rc           ICON 101 + RCDATA 102 (both = ICON/vg.ico)
│   └── vg.manifest     requireAdministrator, Win11 GUID, perMonitorV2
├── tests/
│   ├── cli_test.ps1              84 CLI, lifecycle, registry, enforcement, and uninstall checks
│   ├── rule_collision_test.ps1   55 path/trusted collision and restart checks
│   ├── gui_sync_test.ps1         Native GUI ListView synchronization checks
│   └── driver_protocol_probe.ps1 Raw IOCTL semantics and layout probe
├── IcoBuilder/
│   ├── vg.sys          Third-party driver — PROMOSOFT CORPORATION (2014)
│   └── vg.ico          Base icon (ICO header used as CAB wrapper)
├── images/
│   └── VaultGuard.jpg  Main window screenshot
├── build.ps1           Build script — auto-detects VS + SDK via vswhere.exe
└── LICENSE.md
```

---

## License

**Source code** (`x64/*.asm`, `x64/*.inc`, `x64/vg.rc`, `x64/vg.manifest`, `build.ps1`,
`tests/`, `IcoBuilder/vg.ico`) — **MIT License**.  
See [LICENSE.md](LICENSE.md).

**`IcoBuilder/vg.sys`** — property of **PROMOSOFT CORPORATION**.  
This kernel minifilter driver binary was signed under a cross-signing certificate in 2014.
It is included here solely to enable building and running VaultGuard on supported systems.
All rights to `vg.sys` remain with PROMOSOFT CORPORATION.

---

**Author:** Marek Wesołowski (WESMAR)  
**Contact:** marek@wesolowski.eu.org  
**GitHub:** https://github.com/wesmar/VaultGuard
