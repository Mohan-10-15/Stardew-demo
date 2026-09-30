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

            # The whole reason this script exists.
            if ($ext -eq ".br") {
                $context.Response.Headers.Add("Content-Encoding", "br")
            }

            $bytes = [System.IO.File]::ReadAllBytes($full)
            $context.Response.ContentLength64 = $bytes.Length

            # A HEAD request advertises the length but must not send a body;
            # writing one throws and takes the whole response down with it.
            if ($context.Request.HttpMethod -ne "HEAD") {
                $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            }

            $context.Response.Close()

            Write-Host ("  {0,-6} {1,9} bytes  {2}" -f $context.Request.HttpMethod, $bytes.Length, $relative)
        }
        catch {
            Write-Warning "Request failed: $_"
            try { $context.Response.StatusCode = 500; $context.Response.Close() } catch { }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
