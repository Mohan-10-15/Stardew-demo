<#
.SYNOPSIS
    Serves the Ember Hollow WebGL build and opens it in a browser.

.DESCRIPTION
    Unity's WebGL output is Brotli compressed (.wasm.br, .data.br). The loader
    only decompresses those when the server sends "Content-Encoding: br", so
    opening index.html from the filesystem or from a naive static server fails
    with a blank screen. This script serves the build with the headers the
    loader expects, which is why it exists instead of a one-liner.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\serve-webgl.ps1
    powershell -ExecutionPolicy Bypass -File scripts\serve-webgl.ps1 -Port 8123
#>
[CmdletBinding()]
param(
    [int] $Port = 8000,
    [string] $BuildPath = "",
    [switch] $NoBrowser
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BuildPath)) {
    $BuildPath = Join-Path $PSScriptRoot "..\unity\Builds\WebGL"
}
$BuildPath = (Resolve-Path -LiteralPath $BuildPath).Path

$index = Join-Path $BuildPath "index.html"
if (-not (Test-Path -LiteralPath $index)) {
    throw "No WebGL build found at $BuildPath. Run scripts\build-webgl.ps1 first."
}

$loader = Join-Path $BuildPath "Build\WebGL.loader.js"
if (-not (Test-Path -LiteralPath $loader)) {
    throw "Build is incomplete: $loader is missing. Rebuild rather than serving a partial build."
}

$mime = @{
    ".html"  = "text/html; charset=utf-8"
    ".js"    = "application/javascript; charset=utf-8"
    ".mjs"   = "application/javascript; charset=utf-8"
    ".json"  = "application/json; charset=utf-8"
    ".css"   = "text/css; charset=utf-8"
    ".png"   = "image/png"
    ".jpg"   = "image/jpeg"
    ".ico"   = "image/x-icon"
    ".wasm"  = "application/wasm"
    ".data"  = "application/octet-stream"
    ".br"    = "application/octet-stream"
    ".symbols" = "application/octet-stream"
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host ""
Write-Host "  Ember Hollow is being served from:"
Write-Host "    $BuildPath"
Write-Host ""
Write-Host "  Play it at:  http://localhost:$Port/"
Write-Host "  Stop it with Ctrl+C."
Write-Host ""

if (-not $NoBrowser) {
    Start-Process "http://localhost:$Port/"
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $relative = [System.Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace($relative)) { $relative = "index.html" }

            $target = Join-Path $BuildPath ($relative -replace '/', '\')

            # Refuse anything that escapes the build directory.
            $full = [System.IO.Path]::GetFullPath($target)
            if (-not $full.StartsWith($BuildPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $context.Response.StatusCode = 403
                $context.Response.Close()
                continue
            }

            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                $context.Response.StatusCode = 404
                $context.Response.Close()
                continue
            }

            $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
            $context.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
            $context.Response.Headers.Add("Accept-Ranges", "bytes")
            $context.Response.Headers.Add("Cache-Control", "no-store")

            # The whole reason this script exists.
            if ($ext -eq ".br") {
                $context.Response.Headers.Add("Content-Encoding", "br")
            }

            # Unity's loader streams the .wasm and .data files with byte-range
            # requests. Answering a range with a 200 and the whole body makes the
            # browser abort the connection, which shows up here as
            # "the specified network name is no longer available".
            $total = (Get-Item -LiteralPath $full).Length
            $start = 0L
            $end = $total - 1
            $partial = $false

            $range = $context.Request.Headers["Range"]
            if ($range -match 'bytes=(\d*)-(\d*)') {
                $hasStart = $Matches[1] -ne ""
                $hasEnd = $Matches[2] -ne ""
                if ($hasStart) {
                    $start = [long]$Matches[1]
                }
                if ($hasEnd) {
                    $end = [long]$Matches[2]
                }
                if (-not $hasStart -and $hasEnd) {
                    # Suffix range: the last N bytes.
                    $start = [Math]::Max(0, $total - [long]$Matches[2])
                    $end = $total - 1
                }
                if ($start -ge $total) {
                    $context.Response.StatusCode = 416
                    $context.Response.Headers.Add("Content-Range", "bytes */$total")
                    $context.Response.Close()
                    continue
                }
                if ($end -ge $total) { $end = $total - 1 }
                if ($end -lt $start) { $end = $start }
                $partial = $true
            }

            $length = $end - $start + 1
            if ($partial) {
                $context.Response.StatusCode = 206
                $context.Response.Headers.Add("Content-Range", "bytes $start-$end/$total")
            }
            $context.Response.ContentLength64 = $length

            # A HEAD request advertises the length but must not send a body;
            # writing one throws and takes the whole response down with it.
            if ($context.Request.HttpMethod -ne "HEAD") {
                # Stream in chunks rather than buffering 10 MB, so the first bytes
                # reach the browser immediately and it does not time us out while
                # a single-threaded server is still reading from disk.
                $stream = [System.IO.File]::OpenRead($full)
                try {
                    [void]$stream.Seek($start, [System.IO.SeekOrigin]::Begin)
                    $buffer = New-Object byte[] 65536
                    $remaining = $length
                    while ($remaining -gt 0) {
                        $want = [int][Math]::Min($buffer.Length, $remaining)
                        $read = $stream.Read($buffer, 0, $want)
                        if ($read -le 0) { break }
                        $context.Response.OutputStream.Write($buffer, 0, $read)
                        $remaining -= $read
                    }
                }
                finally {
                    $stream.Dispose()
                }
            }

            $context.Response.Close()
            Write-Host ("  {0,-6} {1,3} {2,10} bytes  {3}" -f $context.Request.HttpMethod, $context.Response.StatusCode, $length, $relative)
        }
        catch {
            $message = $_.Exception.Message
            if ($message -match 'aborted|network name is no longer available|pipe has been ended|Broken pipe|forcibly closed') {
                # A browser that cancels a request is routine, not a fault.
                Write-Host ("  {0,-6} aborted by client  {1}" -f $context.Request.HttpMethod, $relative)
            }
            else {
                Write-Warning "Request failed: $message"
            }

            # Abort rather than try to send a 500: a body may already be partly
            # written, and a status change on a started response throws again.
            try { $context.Response.Abort() } catch { }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
