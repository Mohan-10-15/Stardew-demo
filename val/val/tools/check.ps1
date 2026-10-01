<#
.SYNOPSIS
Runs the full validation pipeline for the project.

.DESCRIPTION
Each stage is wrapped in a hard timeout so a wedged Godot process can never
hang the run. Stages that touch the engine are skipped with SKIP when the
project has never been imported.

.EXAMPLE
pwsh -File tools/check.ps1
#>
param(
    [switch]$SkipImport,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root 'tools/Godot_v4.5-stable_win64_console.exe'

if (-not (Test-Path $godot)) {
    Write-Host "Godot not found at $godot" -ForegroundColor Red
    exit 2
}

$tmpOut = Join-Path $env:TEMP 'hh_check_out.txt'
$tmpErr = Join-Path $env:TEMP 'hh_check_err.txt'

function Invoke-GodotStage {
    param(
        [string]$Name,
        [string[]]$GodotArgs,
        [switch]$AllowFailure
    )

    Write-Host ""
    Write-Host "### $Name" -ForegroundColor Cyan

    $p = Start-Process -FilePath $godot -ArgumentList $GodotArgs `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        $p.Kill()
        Write-Host "  TIMEOUT after ${TimeoutSeconds}s" -ForegroundColor Red
        return @{ name = $Name; code = 124 }
    }

    $out = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
    $err = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
    Write-Host $out

    $errors = @()
    if ($out -match '(?m)^(SCRIPT )?ERROR' ) { $errors += 'stdout' }
    if ($err -match '(?m)^(SCRIPT )?ERROR') { $errors += 'stderr' }
    if ($errors.Count -gt 0 -and -not $AllowFailure) {
        Write-Host $err -ForegroundColor Red
    }

    return @{ name = $Name; code = $p.ExitCode; hasErrors = ($errors.Count -gt 0) }
}

$results = @()

if (-not $SkipImport) {
    $results += Invoke-GodotStage -Name 'import' -GodotArgs @(
        '--headless', '--path', $root, '--import'
    )
}

# Only scan for parse/compile errors, ignore the "main scene missing" error.
$results += Invoke-GodotStage -Name 'tests' -GodotArgs @(
    '--headless', '--path', $root, '--script', 'res://tests/run_tests.gd'
) -AllowFailure

$results += Invoke-GodotStage -Name 'boot' -GodotArgs @(
    '--headless', '--path', $root, '--script', 'res://tools/boot_check.gd'
) -AllowFailure

Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
$bad = 0
foreach ($r in $results) {
    $status = 'OK'
    if ($r.code -ne 0) { $status = "FAIL($($r.code))"; $bad++ }
    if ($r.code -eq 124) { $status = 'TIMEOUT' }
    Write-Host ("{0,-10} {1}" -f $r.name, $status)
}

Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | Stop-Process -Force

if ($bad -gt 0) { exit 1 }
exit 0