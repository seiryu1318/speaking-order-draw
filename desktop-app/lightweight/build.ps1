param([string]$Version)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing

$desktopFolder = Split-Path -Parent $PSScriptRoot
$repoFolder = Split-Path -Parent $desktopFolder
if (!$Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $desktopFolder 'package.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json).version
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a version such as 1.0.8.' }

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The .NET Framework x64 C# compiler is required.'
}

$dist = Join-Path $desktopFolder 'dist'
$buildFolder = Join-Path $dist 'lightweight-build'
[IO.Directory]::CreateDirectory($buildFolder) | Out-Null
$sdkVersion = '1.0.4314.35'
$sdkHash = '90778DEB1B77E36292828B4B5833C9255C27533F40E0DDD55891AE718944EDC4'
$sdkPackage = Join-Path $buildFolder "microsoft.web.webview2.$sdkVersion.nupkg"
if (!(Test-Path -LiteralPath $sdkPackage -PathType Leaf)) {
    $sdkUrl = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$sdkVersion/microsoft.web.webview2.$sdkVersion.nupkg"
    $download = "$sdkPackage.$PID.download"
    Invoke-WebRequest -UseBasicParsing -Uri $sdkUrl -OutFile $download
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $sdkHash) {
        throw 'The downloaded WebView2 SDK does not match the expected package.'
    }
    Move-Item -LiteralPath $download -Destination $sdkPackage -Force
}
if ((Get-FileHash -LiteralPath $sdkPackage -Algorithm SHA256).Hash -ne $sdkHash) {
    throw 'The cached WebView2 SDK does not match the expected package.'
}

$runtimeFiles = [ordered]@{
    'Microsoft.Web.WebView2.Core.dll' = 'lib/net462/Microsoft.Web.WebView2.Core.dll'
    'Microsoft.Web.WebView2.WinForms.dll' = 'lib/net462/Microsoft.Web.WebView2.WinForms.dll'
    'WebView2Loader.dll' = 'runtimes/win-x64/native/WebView2Loader.dll'
    'LICENSE.txt' = 'LICENSE.txt'
    'NOTICE.txt' = 'NOTICE.txt'
}
$sdkFolder = Join-Path $buildFolder "webview2-$sdkVersion"
[IO.Directory]::CreateDirectory($sdkFolder) | Out-Null
$sdkZip = [IO.Compression.ZipFile]::OpenRead($sdkPackage)
try {
    foreach ($file in $runtimeFiles.GetEnumerator()) {
        $entry = $sdkZip.GetEntry($file.Value)
        if (!$entry) { throw "Missing WebView2 SDK file: $($file.Value)" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $sdkFolder $file.Key), $true)
    }
} finally {
    $sdkZip.Dispose()
}

$work = Join-Path $buildFolder "$Version-$PID"
[IO.Directory]::CreateDirectory($work) | Out-Null
$bundle = Join-Path $work 'payload.zip'
$webFiles = @(
    'index.html', '2학년 말하기 제비뽑기.html', 'Sortable.min.js', 'xlsx.full.min.js',
    'html2canvas.min.js', 'manifest.webmanifest', 'manifest-legacy.webmanifest',
    'icon-180.png', 'icon-192.png', 'icon-512.png', 'icon.svg', 'service-worker.js'
)
$zip = [IO.Compression.ZipFile]::Open($bundle, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $webFiles) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, (Join-Path $repoFolder $file), "web/$file", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    foreach ($file in $runtimeFiles.Keys) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, (Join-Path $sdkFolder $file), "runtime/$file", [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}

# Embed a multi-size Windows icon from the project's existing PNG.
$iconPath = Join-Path $work 'draw.ico'
$source = [Drawing.Image]::FromFile((Join-Path $repoFolder 'icon-512.png'))
try {
    $frames = foreach ($size in 16, 32, 48, 64, 128, 256) {
        $bitmap = [Drawing.Bitmap]::new($size, $size)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $stream = [IO.MemoryStream]::new()
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, 0, 0, $size, $size)
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            [pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() }
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
            $stream.Dispose()
        }
    }
} finally {
    $source.Dispose()
}
$writer = [IO.BinaryWriter]::new([IO.File]::Create($iconPath))
try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$frames.Count)
    $offset = 6 + (16 * $frames.Count)
    foreach ($frame in $frames) {
        $dimension = [byte]($frame.Size % 256)
        $writer.Write($dimension)
        $writer.Write($dimension)
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length)
        $writer.Write([uint32]$offset)
        $offset += $frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
} finally {
    $writer.Dispose()
}

$versionSource = Join-Path $work 'Version.g.cs'
[IO.File]::WriteAllText($versionSource, @"
using System.Reflection;
[assembly: AssemblyTitle("제비뽑기")]
[assembly: AssemblyProduct("제비뽑기")]
[assembly: AssemblyDescription("제비뽑기")]
[assembly: AssemblyVersion("$Version.0")]
[assembly: AssemblyFileVersion("$Version.0")]
"@, [Text.Encoding]::UTF8)

$exe = Join-Path $dist "제비뽑기-경량-$Version.exe"
$compilerArgs = @(
    '/nologo', '/target:winexe', '/platform:x64', '/optimize+', '/utf8output', '/codepage:65001',
    "/out:$exe", "/win32icon:$iconPath", "/win32manifest:$(Join-Path $PSScriptRoot 'app.manifest')",
    "/resource:$bundle,Draw.Payload.zip",
    '/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll', '/reference:System.IO.Compression.dll',
    '/reference:System.IO.Compression.FileSystem.dll', '/reference:System.Web.Extensions.dll',
    "/reference:$(Join-Path $sdkFolder 'Microsoft.Web.WebView2.Core.dll')",
    "/reference:$(Join-Path $sdkFolder 'Microsoft.Web.WebView2.WinForms.dll')",
    (Join-Path $PSScriptRoot 'Program.cs'), $versionSource
)
& $compiler @compilerArgs
if ($LASTEXITCODE -ne 0) { throw "C# compilation failed ($LASTEXITCODE)." }
Get-Item -LiteralPath $exe | Select-Object FullName, Length
