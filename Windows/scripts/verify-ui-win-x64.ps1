$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot/.."
$Exe = Join-Path $Root "dist/win-x64/Aviv.Windows.App.exe"
$ScreenshotDir = Join-Path $Root "dist/screenshots"
$Screenshot = Join-Path $ScreenshotDir "windows-ui-verification.png"

if (!(Test-Path $Exe)) {
  throw "Published executable not found: $Exe"
}

New-Item -ItemType Directory -Force -Path $ScreenshotDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$fixture = @'
# Windows Aviv Verification

This text was pasted by the Windows UI verifier into the native WinUI app.

It includes **bold text**, _quiet emphasis_, `inline code`, and [a stable link](https://example.com/windows).

- [x] Real keyboard paste reached the editor
- [ ] Layout should remain calm while syntax is styled

| Block | State |
| --- | --- |
| Table | Rendered |

> The screenshot should show Aviv's calm editor chrome, menu bar, minimap, and typed Markdown.

```text
native windows verifier
```
'@

$process = Start-Process -FilePath $Exe -PassThru
try {
  Start-Sleep -Seconds 6
  [Microsoft.VisualBasic.Interaction]::AppActivate($process.Id) | Out-Null
  Start-Sleep -Milliseconds 500

  Set-Clipboard -Value $fixture
  [System.Windows.Forms.SendKeys]::SendWait("^a")
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Seconds 2

  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save($Screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()

  $file = Get-Item $Screenshot
  if ($file.Length -lt 10000) {
    throw "Screenshot is unexpectedly small: $($file.Length) bytes"
  }

  Write-Host "Captured UI verification screenshot: $Screenshot ($($file.Length) bytes)"
}
finally {
  if (!$process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
