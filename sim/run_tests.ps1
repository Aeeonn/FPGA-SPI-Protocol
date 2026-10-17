# Runs all simulation testbenches with Icarus Verilog on Windows.
#   .\run_tests.ps1                 run all tests
#   .\run_tests.ps1 tb_spi_master   run one test
#   .\run_tests.ps1 -Wave           also dump a VCD and regenerate the waveform SVG
param(
    [string[]]$Tests = @('tb_spi_master', 'tb_led_driver', 'tb_use_accel'),
    [switch]$Wave
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$iverilog = (Get-Command iverilog -ErrorAction SilentlyContinue).Source
if (-not $iverilog -and (Test-Path 'C:\iverilog\bin\iverilog.exe')) { $iverilog = 'C:\iverilog\bin\iverilog.exe' }
if (-not $iverilog) { throw 'iverilog not found. Install Icarus Verilog (winget install Icarus.Verilog).' }
$vvp = Join-Path (Split-Path $iverilog) 'vvp.exe'

$sources = @{
    tb_spi_master = @('tb_spi_master.v', 'adxl345_model.v', '..\spi_master.v')
    tb_led_driver = @('tb_led_driver.v', '..\led_driver.v')
    tb_use_accel  = @('tb_use_accel.v', 'adxl345_model.v', '..\USE_ACCEL.v', '..\adxl345_controller.v',
                      '..\spi_master.v', '..\led_driver.v')
}

New-Item -ItemType Directory -Force build | Out-Null
$failed = @()

foreach ($tb in $Tests) {
    if (-not $sources.ContainsKey($tb)) { throw "Unknown test '$tb'" }
    Write-Host "=== $tb ===" -ForegroundColor Cyan
    & $iverilog -g2012 -s $tb -o "build\$tb.vvp" @($sources[$tb])
    if ($LASTEXITCODE -ne 0) { $failed += $tb; continue }

    $simArgs = @('-n', "$tb.vvp")
    if ($Wave -and $tb -eq 'tb_spi_master') { $simArgs += '+vcd' }
    Push-Location build
    try { & $vvp @simArgs } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { $failed += $tb }
}

if ($Wave) {
    python vcd_to_svg.py build\tb_spi_master.vcd ..\docs\spi_read_waveform.svg
}

Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host "All tests passed: $($Tests -join ', ')" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Failed: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
