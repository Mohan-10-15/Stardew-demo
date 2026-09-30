<#
.SYNOPSIS
    Launches the native Windows build of Ember Hollow as a desktop app.

.DESCRIPTION
    WebGL output can only ever run inside a browser, because it is web
    technology. For a real application window, use the native player that
    WindowsBuilder produces.

    If the build is missing this offers nothing to launch and says so; build it
    first with:

        Unity.exe -batchmode -quit -projectPath unity ^
          -executeMethod EmberHollow.EditorTools.WindowsBuilder.Build ^
          -logFile Logs\windows-build.log

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run-windows.ps1
#>
[CmdletBinding()]
param(
    [string] $BuildPath = "",
    [switch] $Wait
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BuildPath)) {
    $BuildPath = Join-Path $PSScriptRoot "..\unity\Builds\Windows\EmberHollow.exe"
}

$exe = [System.IO.Path]::GetFullPath($BuildPath)

if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    Write-Error "No Windows build at $exe. Build it with EmberHollow.EditorTools.WindowsBuilder.Build first."
    exit 1
}

$sizeMb = [math]::Round((Get-Item -LiteralPath $exe).Length / 1MB, 1)
$stamp = (Get-Item -LiteralPath $exe).LastWriteTime
Write-Host ""
Write-Host "  Ember Hollow (native Windows build)"
Write-Host "    $exe"
Write-Host "    $sizeMb MB, built $stamp"
Write-Host ""

$process = Start-Process -FilePath $exe -PassThru

if ($Wait) {
    Write-Host "  Running as pid $($process.Id). Close the game window to exit."
    $process.WaitForExit()
}
else {
    Write-Host "  Running as pid $($process.Id)."
}
