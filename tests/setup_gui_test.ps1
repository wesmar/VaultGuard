#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$regPath = 'HKCU:\Software\VG\Trusted'
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

Write-Host "Inicjalizacja 37 aktywnych procesów testowych..." -ForegroundColor Cyan
1..37 | ForEach-Object {
    $name = ('test{0:D2}.exe' -f $_)
    Set-ItemProperty -Path $regPath -Name $name -Value 1 -Type DWord
}

Write-Host "Dodawanie 1 wyłączonego procesu (test_disabled.exe)..." -ForegroundColor Cyan
Set-ItemProperty -Path $regPath -Name 'test_disabled.exe' -Value 0 -Type DWord

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Green
Write-Host "  Stan testowy przygotowany pomyślnie!" -ForegroundColor Green
Write-Host "  Aktywne procesy : 37 (limit osiągnięty)" -ForegroundColor Gray
Write-Host "  Wyłączony proces: test_disabled.exe" -ForegroundColor Gray
Write-Host "=======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Uruchom GUI:                   .\bin\vg.exe" -ForegroundColor Yellow
Write-Host "Po zakończeniu testu uruchom:  .\clean_gui_test.ps1" -ForegroundColor Yellow
