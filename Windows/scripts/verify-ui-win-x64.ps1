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

public static class AvivNativeWindow {
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool SetForegroundWindow(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  [DllImport("user32.dll")]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
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

  Set-Clipboard -Value $fixture
  [System.Windows.Forms.SendKeys]::SendWait("^a")
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Seconds 2
  [AvivNativeWindow]::SetWindowPos($handle, [AvivNativeWindow]::HWND_TOPMOST, 96, 72, 1160, 760, 0x0040) | Out-Null
  [AvivNativeWindow]::SetForegroundWindow($handle) | Out-Null
  Start-Sleep -Milliseconds 300

  $rect = [AvivNativeWindow+RECT]::new()
  if (![AvivNativeWindow]::GetWindowRect($handle, [ref]$rect)) {
    throw "Could not read Aviv window bounds for screenshot."
  }

  $width = [Math]::Max(1, $rect.Right - $rect.Left)
  $height = [Math]::Max(1, $rect.Bottom - $rect.Top)
  $bitmap = [System.Drawing.Bitmap]::new($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen([System.Drawing.Point]::new($rect.Left, $rect.Top), [System.Drawing.Point]::Empty, [System.Drawing.Size]::new($width, $height))
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
