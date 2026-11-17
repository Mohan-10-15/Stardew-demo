# Unity-free verification of the engine-free Core tier.
# Requires the .NET 8 SDK. Run from anywhere:
#   powershell -ExecutionPolicy Bypass -File scripts\verify-core.ps1
$ErrorActionPreference = 'Stop'

$project = Join-Path $PSScriptRoot '..\tools\core-verify\EmberCoreVerify.csproj'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'The .NET 8 SDK is required to verify EmberHollow.Core without Unity.'
}

dotnet run --project $project -c Release
if ($LASTEXITCODE -ne 0) {
    throw "Core verification failed (exit $LASTEXITCODE)."
}
