$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectPath = Split-Path $PSScriptRoot -Parent
$navy = [System.Drawing.ColorTranslator]::FromHtml('#14234B')
$white = [System.Drawing.Color]::White

function New-RoundedPath([single]$x, [single]$y, [single]$width, [single]$height, [single]$radius) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $radius * 2
    $path.AddArc($x, $y, $diameter, $diameter, 180, 90)
    $path.AddArc($x + $width - $diameter, $y, $diameter, $diameter, 270, 90)
    $path.AddArc($x + $width - $diameter, $y + $height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($x, $y + $height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return ,$path
}

function Fill-RoundedRect($graphics, $brush, [single]$x, [single]$y, [single]$width, [single]$height, [single]$radius) {
    $path = New-RoundedPath $x $y $width $height $radius
    try { $graphics.FillPath($brush, $path) } finally { $path.Dispose() }
}

foreach ($size in @(180, 192, 512)) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $navyBrush = [System.Drawing.SolidBrush]::new($navy)
    $whiteBrush = [System.Drawing.SolidBrush]::new($white)
    $outline = [System.Drawing.Pen]::new($navy, 12)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $scale = [single]($size / 512.0)
        $graphics.ScaleTransform($scale, $scale)

        Fill-RoundedRect $graphics $navyBrush 0 0 512 512 96
        Fill-RoundedRect $graphics $whiteBrush 108 96 268 320 16
        Fill-RoundedRect $graphics $navyBrush 148 152 188 18 3
        Fill-RoundedRect $graphics $navyBrush 148 207 152 18 3
        Fill-RoundedRect $graphics $navyBrush 148 262 83 18 3
        Fill-RoundedRect $graphics $navyBrush 148 317 83 18 3

        $badge = New-RoundedPath 258 266 150 150 10
        try {
            $graphics.FillPath($whiteBrush, $badge)
            $graphics.DrawPath($outline, $badge)
        } finally { $badge.Dispose() }

        $points = [System.Drawing.PointF[]]@(
            [System.Drawing.PointF]::new(309, 315),
            [System.Drawing.PointF]::new(336, 295),
            [System.Drawing.PointF]::new(357, 295),
            [System.Drawing.PointF]::new(357, 372),
            [System.Drawing.PointF]::new(379, 372),
            [System.Drawing.PointF]::new(379, 389),
            [System.Drawing.PointF]::new(312, 389),
            [System.Drawing.PointF]::new(312, 372),
            [System.Drawing.PointF]::new(335, 372),
            [System.Drawing.PointF]::new(335, 317),
            [System.Drawing.PointF]::new(318, 329)
        )
        $graphics.FillPolygon($navyBrush, $points)
        $bitmap.Save((Join-Path $projectPath "icon-$size.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $outline.Dispose()
        $whiteBrush.Dispose()
        $navyBrush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

Get-Item -LiteralPath (Join-Path $projectPath 'icon-180.png'), (Join-Path $projectPath 'icon-192.png'), (Join-Path $projectPath 'icon-512.png') |
    Select-Object Name, Length
