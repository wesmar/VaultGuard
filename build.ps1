#Requires -Version 5.1
param(
    [switch]$SkipRC
)

$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Banner {
    param([string]$Text, [string]$Color = 'Cyan')
    $line = '=' * 44
    Write-Host ''
    Write-Host $line  -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host $line  -ForegroundColor $Color
}

# ── Locate MSVC toolchain ─────────────────────────────────────────────────────

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    Write-Host "ERROR: vswhere.exe not found: $vswhere" -ForegroundColor Red; exit 1
}

$VSInstall = & $vswhere -latest -property installationPath
if (-not $VSInstall) {
    Write-Host 'ERROR: vswhere found no VS installation' -ForegroundColor Red; exit 1
}

$MSVCRoot = Join-Path $VSInstall 'VC\Tools\MSVC'
if (-not (Test-Path $MSVCRoot)) {
    Write-Host "ERROR: MSVC root not found: $MSVCRoot" -ForegroundColor Red; exit 1
}

$MSVCVer = Get-ChildItem $MSVCRoot -Directory |
    Where-Object  { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object   { [Version]$_.Name } -Descending |
    Select-Object -First 1 -ExpandProperty Name

if (-not $MSVCVer) {
    Write-Host "ERROR: no MSVC toolchain found under $MSVCRoot" -ForegroundColor Red; exit 1
}

$VsBase  = "$MSVCRoot\$MSVCVer\bin\Hostx64"
$Ml64    = "$VsBase\x64\ml64.exe"
$Link64  = "$VsBase\x64\link.exe"
$Dumpbin = "$VsBase\x64\dumpbin.exe"

foreach ($tool in $Ml64, $Link64, $Dumpbin) {
    if (-not (Test-Path $tool)) {
        Write-Host "ERROR: tool not found: $tool" -ForegroundColor Red; exit 1
    }
}

# ── Locate Windows SDK ────────────────────────────────────────────────────────

$SdkLibRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\Lib"
$SdkVer = Get-ChildItem $SdkLibRoot -Directory |
    Where-Object  { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
    Sort-Object   { [Version]$_.Name } -Descending |
    Select-Object -First 1 -ExpandProperty Name

if (-not $SdkVer) {
    Write-Host "ERROR: no SDK version found under $SdkLibRoot" -ForegroundColor Red; exit 1
}

$SdkBase    = "$SdkLibRoot\$SdkVer"
$SdkBin     = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\$SdkVer\x64"
$SdkInclude = "${env:ProgramFiles(x86)}\Windows Kits\10\Include\$SdkVer"
$LibPath    = "$SdkBase\um\x64"

$env:PATH    += ";$SdkBin"
$env:INCLUDE  = "$SdkInclude\um;$SdkInclude\shared"

# ── Output dir ────────────────────────────────────────────────────────────────

$OutDir = Join-Path $ScriptDir 'bin'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

$IconDir = Join-Path $ScriptDir 'ICON'
if (-not (Test-Path $IconDir)) { New-Item -ItemType Directory -Path $IconDir | Out-Null }

# ── Build summary ─────────────────────────────────────────────────────────────

Write-Banner 'Vault Guard — vg.exe build'
Write-Host "  VS      : $VSInstall" -ForegroundColor Gray
Write-Host "  MSVC    : $MSVCVer"   -ForegroundColor Gray
Write-Host "  SDK     : $SdkVer"    -ForegroundColor Gray

$StartTime = Get-Date
$OK        = $true

# ── Step 0: Package driver into icon payload ──────────────────────────────────
#
# Compresses vg.sys into an LZX CAB, then writes:
#   [first $HeaderBytes of base .ico] + [CAB bytes]  →  ICON\vg.ico
#
# The loader reads the icon, seeks past the header and expands the CAB
# to recover vg.sys at install time.  $HeaderBytes must match exactly
# what the loader expects (1662 = standard single-image .ico header).

function Build-DriverIcon {
    param(
        [string] $DriverPath,
        [string] $BaseIcon,
        [string] $OutIcon,
        [int]    $HeaderBytes = 1078
    )

    foreach ($f in $DriverPath, $BaseIcon) {
        if (-not (Test-Path $f)) {
            Write-Host "ERROR: required file not found: $f" -ForegroundColor Red
            return $false
        }
    }

    $iconData = [System.IO.File]::ReadAllBytes($BaseIcon)
    if ($iconData.Length -lt $HeaderBytes) {
        Write-Host "ERROR: base icon is $($iconData.Length) B; need >= $HeaderBytes B" -ForegroundColor Red
        return $false
    }

    $tmpDir = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "sf_drv_$([System.IO.Path]::GetRandomFileName())"
    )
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    try {
        $tmpSys = Join-Path $tmpDir 'vg.sys'
        Copy-Item $DriverPath $tmpSys -Force

        $ddf = ".Set CabinetNameTemplate=vg.cab`r`n" +
               ".Set DiskDirectoryTemplate=$tmpDir`r`n" +
               ".Set CompressionType=LZX`r`n" +
               ".Set CompressionMemory=21`r`n" +
               ".Set MaxCabinetSize=0`r`n" +
               ".Set Cabinet=on`r`n" +
               ".Set Compress=on`r`n" +
               "`"$tmpSys`" vg.sys`r`n"

        $ddfPath = Join-Path $tmpDir 'pkg.ddf'
        [System.IO.File]::WriteAllText($ddfPath, $ddf, [System.Text.Encoding]::ASCII)

        $p = Start-Process makecab.exe -ArgumentList '/F', "`"$ddfPath`"" `
                           -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            Write-Host "ERROR: makecab.exe exited $($p.ExitCode)" -ForegroundColor Red
            return $false
        }

        $cabPath = Join-Path $tmpDir 'vg.cab'
        if (-not (Test-Path $cabPath)) {
            Write-Host "ERROR: CAB not produced at expected path: $cabPath" -ForegroundColor Red
            return $false
        }

        $cabData  = [System.IO.File]::ReadAllBytes($cabPath)
        $combined = [byte[]]::new($HeaderBytes + $cabData.Length)
        [Array]::Copy($iconData, 0,           $combined, 0,            $HeaderBytes)
        [Array]::Copy($cabData,  0,           $combined, $HeaderBytes, $cabData.Length)

        $outDir = [System.IO.Path]::GetDirectoryName($OutIcon)
        if ($outDir -and -not [System.IO.Directory]::Exists($outDir)) {
            [System.IO.Directory]::CreateDirectory($outDir) | Out-Null
        }
        [System.IO.File]::WriteAllBytes($OutIcon, $combined)

        Write-Host "  Driver : $DriverPath ($((Get-Item $DriverPath).Length) B)" -ForegroundColor Gray
        Write-Host "  Icon   : ${HeaderBytes} B header + $($cabData.Length) B CAB = $($combined.Length) B" -ForegroundColor Gray
        return $true

    } finally {
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $SkipRC) {
    Write-Banner '[0] Packaging vg.sys into icon'
    $OK = Build-DriverIcon `
        -DriverPath   (Join-Path $ScriptDir 'IcoBuilder\vg.sys') `
        -BaseIcon     'IcoBuilder\vg.ico' `
        -OutIcon      (Join-Path $ScriptDir 'ICON\vg.ico')
}

# ── Steps 1–4 run from $ScriptDir (relative paths throughout) ─────────────────

Push-Location $ScriptDir
try {

    # ── Step 1: Compile resources ─────────────────────────────────────────────

    if ($SkipRC) {
        Write-Host '[1] Resources — SKIPPED' -ForegroundColor DarkGray
        if (-not (Test-Path 'vg.res')) {
            Write-Host 'ERROR: vg.res missing — cannot skip RC step' -ForegroundColor Red
            exit 1
        }
    } elseif ($OK) {
        Write-Banner '[1] Compiling resources'
        & rc /c65001 /I "$SdkInclude\um" /I "$SdkInclude\shared" /fo vg.res x64\vg.rc
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'ERROR: rc.exe failed' -ForegroundColor Red
            $OK = $false
        }
    }

    # ── Step 2: Assemble ──────────────────────────────────────────────────────

    $Modules = @('strutil', 'res', 'driver_scm', 'device', 'ioctl', 'config', 'cli', 'export', 'service', 'theme', 'listview', 'handlers', 'drop', 'tray', 'layout', 'procpicker', 'impexp', 'window', 'main')

    if ($OK) {
        Write-Banner '[2] Assembling modules'
        foreach ($m in $Modules) {
            Write-Host "    x64\$m.asm" -ForegroundColor Gray
            & $Ml64 /c /Cp /Cx /Zi /I x64 /Fo "x64\$m.obj" "x64\$m.asm"
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERROR: ml64 failed on $m.asm" -ForegroundColor Red
                $OK = $false
                break
            }
        }
    }

    # ── Step 3: Link ──────────────────────────────────────────────────────────

    if ($OK) {
        Write-Banner '[3] Linking'

        $objs = $Modules | ForEach-Object { "x64\$_.obj" }

        & $Link64 @objs `
            'vg.res' `
            '/subsystem:windows' `
            '/entry:mainCRTStartup' `
            '/nodefaultlib' `
            '/Brepro' `
            '/out:bin\vg.exe' `
            '/MANIFEST:EMBED' `
            '/MANIFESTINPUT:x64\vg.manifest' `
            "/MANIFESTUAC:level='requireAdministrator' uiAccess='false'" `
            "/LIBPATH:$LibPath" `
            'kernel32.lib' 'user32.lib'  'advapi32.lib' 'shell32.lib' `
            'ole32.lib'    'dwmapi.lib'  'gdi32.lib'    'comctl32.lib' `
            'uxtheme.lib'  'cabinet.lib' 'comdlg32.lib'

        if ($LASTEXITCODE -ne 0) {
            Write-Host 'ERROR: link.exe failed' -ForegroundColor Red
            $OK = $false
        }
    }

    # ── Step 4: Verify imports ────────────────────────────────────────────────

    $BlockedPatterns = 'msvcr|vcruntime|ucrtbase|rstrtmgr'
    $AllowedDlls = [System.Collections.Generic.HashSet[string]]([StringComparer]::OrdinalIgnoreCase)
    @('CABINET.dll','ADVAPI32.dll','COMCTL32.dll','COMDLG32.dll','DWMAPI.dll','GDI32.dll',
      'KERNEL32.dll','OLE32.dll','SHELL32.dll','USER32.dll','UXTHEME.dll') |
        ForEach-Object { [void]$AllowedDlls.Add($_) }

    if ($OK) {
        Write-Banner '[4] Verifying imports'

        $exePath    = 'bin\vg.exe'
        $imports    = & $Dumpbin /imports    $exePath
        $dependents = & $Dumpbin /dependents $exePath

        $blocked = $imports | Select-String $BlockedPatterns
        if ($blocked) {
            $blocked | ForEach-Object { Write-Host "ERROR: blocked import: $_" -ForegroundColor Red }
            $OK = $false
        } else {
            Write-Host '[PASS] No CRT imports' -ForegroundColor Green
        }

        $actualDlls = $dependents |
            ForEach-Object { if ($_ -match '^\s*([A-Za-z0-9_.-]+\.dll)\s*$') { $Matches[1] } } |
            Sort-Object -Unique

        $unexpected = $actualDlls | Where-Object { -not $AllowedDlls.Contains($_) }
        if ($unexpected) {
            $unexpected | ForEach-Object { Write-Host "ERROR: unexpected DLL: $_" -ForegroundColor Red }
            $OK = $false
        } else {
            Write-Host '[PASS] Dependent DLL set clean' -ForegroundColor Green
        }
        Write-Host "      Deps: $($actualDlls -join ', ')" -ForegroundColor Gray
    }

} finally {
    Pop-Location
}

# ── Cleanup intermediates ─────────────────────────────────────────────────────

Write-Host ''
Write-Host '>>> Cleaning intermediates...' -ForegroundColor Yellow
Remove-Item "$ScriptDir\x64\*.obj" -ErrorAction SilentlyContinue
Remove-Item "$ScriptDir\*.res"     -ErrorAction SilentlyContinue
Remove-Item "$ScriptDir\x64\*.pdb" -ErrorAction SilentlyContinue

# ── Result ────────────────────────────────────────────────────────────────────

$elapsed = [int]((Get-Date) - $StartTime).TotalSeconds
Write-Host ''
if ($OK) {
    $size = (Get-Item "$ScriptDir\bin\vg.exe").Length
    Write-Banner "BUILD COMPLETE  (${elapsed}s)" 'Green'
    Write-Host "  Output : bin\vg.exe  ($size B)" -ForegroundColor Green
    Write-Host ('=' * 44) -ForegroundColor Green
    exit 0
} else {
    Write-Banner 'BUILD FAILED' 'Red'
    exit 1
}
