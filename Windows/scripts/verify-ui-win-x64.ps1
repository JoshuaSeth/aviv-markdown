$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot/.."
$Exe = Join-Path $Root "dist/win-x64/Aviv.Windows.App.exe"
$ScreenshotDir = Join-Path $Root "dist/screenshots"
$Screenshot = Join-Path $ScreenshotDir "windows-ui-verification.png"
$DiagnosticLog = Join-Path $ScreenshotDir "windows-ui-verification.log"

if (!(Test-Path $Exe)) {
  throw "Published executable not found: $Exe"
}

New-Item -ItemType Directory -Force -Path $ScreenshotDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $DiagnosticLog

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class AvivNativeWindow {
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
}
"@

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

$env:AVIV_DIAGNOSTIC_LOG = $DiagnosticLog
$process = Start-Process -FilePath $Exe -PassThru
try {
  $handle = [IntPtr]::Zero
  for ($attempt = 0; $attempt -lt 120; $attempt++) {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    if ($process.HasExited) {
      if (Test-Path $DiagnosticLog) {
        Write-Host "Aviv diagnostic log:"
        Get-Content $DiagnosticLog | ForEach-Object { Write-Host $_ }
      }
      throw "Aviv exited before exposing a window. ExitCode=$($process.ExitCode)"
    }

    if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
      $handle = $process.MainWindowHandle
      break
    }

    $matchingProcess = Get-Process -Name "Aviv.Windows.App" -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
      Select-Object -First 1
    if ($matchingProcess) {
      $handle = $matchingProcess.MainWindowHandle
      break
    }
  }

  if ($handle -eq [IntPtr]::Zero) {
    $process.Refresh()
    if (Test-Path $DiagnosticLog) {
      Write-Host "Aviv diagnostic log:"
      Get-Content $DiagnosticLog | ForEach-Object { Write-Host $_ }
    }
    $knownProcesses = Get-Process -Name "Aviv.Windows.App" -ErrorAction SilentlyContinue |
      Select-Object Id, ProcessName, HasExited, MainWindowHandle, StartTime |
      Format-Table -AutoSize |
      Out-String
    throw "Aviv window handle was not available after launch. Main process HasExited=$($process.HasExited). Matching processes:`n$knownProcesses"
  }

  [AvivNativeWindow]::ShowWindow($handle, 9) | Out-Null
  [AvivNativeWindow]::SetWindowPos($handle, [AvivNativeWindow]::HWND_TOPMOST, 96, 72, 1160, 760, 0x0040) | Out-Null
  [AvivNativeWindow]::SetForegroundWindow($handle) | Out-Null
  Start-Sleep -Milliseconds 500
  $titleBuilder = [System.Text.StringBuilder]::new(256)
  [AvivNativeWindow]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity) | Out-Null
  Write-Host "Using Aviv window handle $handle with title '$($titleBuilder.ToString())'"

  Set-Clipboard -Value $fixture
  [System.Windows.Forms.SendKeys]::SendWait("^a")
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Seconds 2
  [AvivNativeWindow]::SetWindowPos($handle, [AvivNativeWindow]::HWND_TOPMOST, 96, 72, 1160, 760, 0x0040) | Out-Null
  [AvivNativeWindow]::SetForegroundWindow($handle) | Out-Null
  Start-Sleep -Milliseconds 300

  $left = 96
  $top = 72
  $width = 1160
  $height = 760
  $bitmap = [System.Drawing.Bitmap]::new($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $hdc = $graphics.GetHdc()
  try {
    $printed = [AvivNativeWindow]::PrintWindow($handle, $hdc, 2)
  }
  finally {
    $graphics.ReleaseHdc($hdc)
  }

  if (!$printed) {
    Write-Host "PrintWindow returned false; falling back to fixed screen crop."
    $graphics.CopyFromScreen([System.Drawing.Point]::new($left, $top), [System.Drawing.Point]::Empty, [System.Drawing.Size]::new($width, $height))
  }

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
  if (Test-Path $DiagnosticLog) {
    Write-Host "Aviv diagnostic log:"
    Get-Content $DiagnosticLog | ForEach-Object { Write-Host $_ }
  }
  if (!$process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
