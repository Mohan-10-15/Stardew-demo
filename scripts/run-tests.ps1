param(
    [ValidateSet('EditMode', 'PlayMode', 'All')]
    [string]$Platform = 'All'
)

$ErrorActionPreference = 'Stop'

$Unity = 'C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe'
$Project = 'C:\mohan\Game\Stardew dmeo\unity'
$ArtifactDir = Join-Path $Project 'Logs\TestResults'

if (-not (Test-Path -LiteralPath $Unity)) {
    throw "Unity Editor not found at $Unity"
}
if (-not (Test-Path -LiteralPath $Project)) {
    throw "Unity project not found at $Project"
}

New-Item -ItemType Directory -Path $ArtifactDir -Force | Out-Null

$platforms = if ($Platform -eq 'All') { @('EditMode', 'PlayMode') } else { @($Platform) }

$failed = $false

foreach ($p in $platforms) {
    $results = Join-Path $ArtifactDir "$p-results.xml"
    $log = Join-Path $ArtifactDir "$p-run.log"
    Remove-Item $results, $log -ErrorAction SilentlyContinue

    Write-Host "=== Running $p tests ===" -ForegroundColor Cyan

    $args = @(
        '-batchmode',
        '-projectPath', "`"$Project`"",
        '-runTests',
        '-testPlatform', $p,
        '-testResults', "`"$results`"",
        '-logFile', "`"$log`""
    )

    $process = Start-Process -FilePath $Unity -ArgumentList $args -PassThru -WindowStyle Hidden
    $process.WaitForExit()

    if (-not (Test-Path -LiteralPath $results)) {
        Write-Host "$p : NO RESULTS FILE - see $log" -ForegroundColor Red
        $failed = $true
        continue
    }

    [xml]$xml = Get-Content $results
    $run = $xml.'test-run'

    $summary = [pscustomobject]@{
        Platform = $p
        Total    = [int]$run.total
        Passed   = [int]$run.passed
        Failed   = [int]$run.failed
        Skipped  = [int]$run.skipped
        Result   = $run.result
    }

    $summary | Format-Table -AutoSize | Out-String | Write-Host

    if ($summary.Failed -gt 0 -or $summary.Result -ne 'Passed') {
        Write-Host "$p : FAILED" -ForegroundColor Red
        $failed = $true
    }
    else {
        Write-Host "$p : PASSED ($($summary.Passed)/$($summary.Total))" -ForegroundColor Green
    }
}

if ($failed) {
    Write-Host 'RESULT: FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'RESULT: ALL PASSED' -ForegroundColor Green
exit 0
