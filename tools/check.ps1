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

# The project is a .NET project (config/features carries "C#"), so the console
# wrapper is the mono build. The plain GDScript-only build is still accepted as
# a fallback so a machine without the .NET binary can run the suite — it simply
# skips building the C# assembly, which means any case that needs the C# system
# will report it missing rather than silently passing.
$godotCandidates = @(
    (Join-Path $root 'tools/Godot_v4.5-stable_mono_win64_console.exe'),
    (Join-Path $root 'tools/Godot_v4.5-stable_win64_console.exe')
)
$godot = $godotCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $godot) {
    Write-Host "Godot not found. Looked for:" -ForegroundColor Red
    foreach ($c in $godotCandidates) { Write-Host "  $c" -ForegroundColor Red }
    exit 2
}

Write-Host "Engine: $(Split-Path $godot -Leaf)" -ForegroundColor DarkGray

# `Start-Process -ArgumentList @(...)` joins the array with bare spaces and does
# NOT quote elements that contain spaces, so Godot received
# `--path C:\mohan\Game\Stardew dmeo\...`, truncated the path at the first
# space and aborted with 'Invalid project path specified'. Any project path
# containing a space made all three stages fail. Every path argument is
# therefore pre-quoted here.
$quotedRoot = '"' + $root + '"'

$tmpOut = Join-Path $env:TEMP 'hh_check_out.txt'
$tmpErr = Join-Path $env:TEMP 'hh_check_err.txt'

function Invoke-GodotStage {
    param(
        [string]$Name,
        [string[]]$GodotArgs,
        [string[]]$AllowedErrorPattern = @()
    )

    Write-Host ""
    Write-Host "### $Name" -ForegroundColor Cyan

    # Touching .Handle caches the process handle so ExitCode is readable later;
    # without it a -PassThru process reports a null ExitCode even after exiting.
    $p = Start-Process -FilePath $godot -ArgumentList $GodotArgs `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
    $null = $p.Handle

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        $p.Kill()
        Write-Host "  TIMEOUT after ${TimeoutSeconds}s" -ForegroundColor Red
        return @{ name = $Name; code = 124; hasErrors = $true }
    }
    # Parameterless WaitForExit flushes the async output readers, so the
    # redirected files are complete and ExitCode is populated.
    $p.WaitForExit()

    $out = Get-Content $tmpOut -Raw -ErrorAction SilentlyContinue
    $err = Get-Content $tmpErr -Raw -ErrorAction SilentlyContinue
    Write-Host $out

    # A compile error is written to stderr as "SCRIPT ERROR:" and does NOT
    # necessarily change the exit code. Gating on the exit code alone let a
    # broken scene report a clean boot, so stderr is scanned as well.
    $combined = "$out`n$err"
    $violations = @()
    foreach ($stream in @(@{ n = 'stdout'; t = $out }, @{ n = 'stderr'; t = $err })) {
        if ($stream.t -notmatch '(?m)^(SCRIPT )?ERROR') { continue }
        $lines = @($stream.t -split "`r?`n" | Where-Object { $_ -match '^(SCRIPT )?ERROR' })
        $unexpected = @($lines | Where-Object {
            $line = $_
            -not ($AllowedErrorPattern | Where-Object { $line -match $_ })
        })
        if ($unexpected.Count -gt 0) {
            $violations += $unexpected
        }
    }

    if ($violations.Count -gt 0) {
        Write-Host "--- stderr ---" -ForegroundColor Red
        Write-Host $err -ForegroundColor Red
        Write-Host "--- $($violations.Count) error line(s) not allowed for stage '$Name' ---" -ForegroundColor Red
    }

    $code = $p.ExitCode
    if ($null -eq $code) { $code = -1 }
    return @{ name = $Name; code = $code; hasErrors = ($violations.Count -gt 0) }
}

$results = @()

# The C# assembly has to exist before anything can load a C# script, and before
# the import scan can register `BalanceSweep` as a global class — Godot reflects
# over the built DLL to find `[GlobalClass]` types. So the build comes first:
# build, import, test, boot. `dotnet build` rather than `--build-solutions`,
# because this stage must also catch a compile error in a .cs file —
# `--build-solutions` reports through the editor's own output, which this script
# does not scan.
$csproj = Join-Path $root 'Hollowbrook.csproj'
if (Test-Path $csproj) {
    Write-Host ""
    Write-Host "### build (C#)" -ForegroundColor Cyan
    $buildOut = & dotnet build $csproj -v minimal --nologo 2>&1 | Out-String
    Write-Host $buildOut
    $buildBad = ($LASTEXITCODE -ne 0) -or ($buildOut -match '(?m)^\s*error\s')
    if ($buildBad) {
        Write-Host "--- C# build failed ---" -ForegroundColor Red
    }
    $results += @{ name = 'csharp'; code = $(if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 0 }); hasErrors = [bool]$buildBad }
}

if (-not $SkipImport) {
    $results += Invoke-GodotStage -Name 'import' -GodotArgs @(
        '--headless', '--path', $quotedRoot, '--import'
    )
}

# A `--script` run has no main scene, so Godot logs that one error harmlessly
# before the script runs. It is the only error these stages may emit.
$scriptRunNoise = @('ERROR: .*main scene', 'ERROR: No main scene')

$results += Invoke-GodotStage -Name 'tests' -GodotArgs @(
    '--headless', '--path', $quotedRoot, '--script', 'res://tests/run_tests.gd'
) -AllowedErrorPattern $scriptRunNoise

$results += Invoke-GodotStage -Name 'boot' -GodotArgs @(
    '--headless', '--path', $quotedRoot, '--script', 'res://tools/boot_check.gd'
) -AllowedErrorPattern $scriptRunNoise

Write-Host ""
Write-Host "========== SUMMARY ==========" -ForegroundColor Cyan
$bad = 0
foreach ($r in $results) {
    $status = 'OK'
    if ($r.code -eq 124) {
        $status = 'TIMEOUT'
        $bad++
    }
    elseif ($r.code -ne 0) {
        $status = "FAIL(exit $($r.code))"
        $bad++
    }
    elseif ($r.hasErrors) {
        # Exit code was 0 but the engine logged a compile/script error. This is
        # the case that previously reported a clean boot on a broken scene.
        $status = 'FAIL(script errors)'
        $bad++
    }
    Write-Host ("{0,-10} {1}" -f $r.name, $status)
}

Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | Stop-Process -Force

if ($bad -gt 0) { exit 1 }
exit 0