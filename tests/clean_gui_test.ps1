#Requires -Version 5.1
$ErrorActionPreference = 'SilentlyContinue'

$regPath = 'HKCU:\Software\VG\Trusted'
if (Test-Path $regPath) {
    1..37 | ForEach-Object {
        $name = ('test{0:D2}.exe' -f $_)
        Remove-ItemProperty -Path $regPath -Name $name -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -Path $regPath -Name 'test_disabled.exe' -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "  Wpisy testowe zostały usunięte z rejestru." -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
