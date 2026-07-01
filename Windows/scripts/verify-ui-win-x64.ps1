$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot/.."
$Exe = Join-Path $Root "dist/win-x64/Aviv.Windows.App.exe"
$ScreenshotDir = Join-Path $Root "dist/screenshots"
$Screenshot = Join-Path $ScreenshotDir "windows-ui-verification.png"
$ImmediateScreenshot = Join-Path $ScreenshotDir "windows-ui-immediate-after-launch.png"
$LaunchScreenshot = Join-Path $ScreenshotDir "windows-ui-after-launch.png"
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
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class AvivNativeWindow {
  public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
  public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

  private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

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

  [DllImport("kernel32.dll")]
  public static extern IntPtr GetConsoleWindow();

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);

  [DllImport("user32.dll")]
  private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  [DllImport("user32.dll")]
  private static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  private static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

  [DllImport("user32.dll")]
  private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

  public static string DescribeWindow(IntPtr hWnd) {
    var title = new StringBuilder(256);
    GetWindowText(hWnd, title, title.Capacity);

    var className = new StringBuilder(256);
    GetClassName(hWnd, className, className.Capacity);

    RECT rect;
    var rectText = GetWindowRect(hWnd, out rect)
      ? string.Format("{0},{1},{2},{3} {4}x{5}", rect.Left, rect.Top, rect.Right, rect.Bottom, rect.Right - rect.Left, rect.Bottom - rect.Top)
      : "unavailable";

    return string.Format("hwnd={0} visible={1} iconic={2} class='{3}' title='{4}' rect={5}",
      hWnd, IsWindowVisible(hWnd), IsIconic(hWnd), className.ToString(), title.ToString(), rectText);
  }

  public static string[] DescribeTopLevelWindows(int processId) {
    var lines = new List<string>();
    EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
      uint windowProcessId;
      GetWindowThreadProcessId(hWnd, out windowProcessId);
      if (windowProcessId == (uint)processId) {
        lines.Add(DescribeWindow(hWnd));
      }

      return true;
    }, IntPtr.Zero);

    return lines.ToArray();
  }

  public static IntPtr FindLargestVisibleWindow(int processId) {
    IntPtr bestHandle = IntPtr.Zero;
    long bestArea = -1;
    EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
      uint windowProcessId;
      GetWindowThreadProcessId(hWnd, out windowProcessId);
      if (windowProcessId != (uint)processId || !IsWindowVisible(hWnd) || IsIconic(hWnd)) {
        return true;
      }

      RECT rect;
      if (!GetWindowRect(hWnd, out rect)) {
        return true;
      }

      var area = (long)Math.Max(0, rect.Right - rect.Left) * Math.Max(0, rect.Bottom - rect.Top);
      if (area > bestArea) {
        bestArea = area;
        bestHandle = hWnd;
      }

      return true;
    }, IntPtr.Zero);

    return bestHandle;
  }
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

function Save-FixedScreenCapture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  $left = 96
  $top = 72
  $width = 1160
  $height = 760
  $bitmap = [System.Drawing.Bitmap]::new($width, $height)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen([System.Drawing.Point]::new($left, $top), [System.Drawing.Point]::Empty, [System.Drawing.Size]::new($width, $height))
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }

  $file = Get-Item $Path
  Write-Host "Captured $Label screenshot: $Path ($($file.Length) bytes)"
}

function Move-BlockingWindowsOutOfCapture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Stage
  )

  $consoleHandle = [AvivNativeWindow]::GetConsoleWindow()
  if ($consoleHandle -ne [IntPtr]::Zero) {
    Write-Host "Moving verifier console window $consoleHandle out of capture ($Stage)."
    [AvivNativeWindow]::ShowWindow($consoleHandle, 1) | Out-Null
    [AvivNativeWindow]::SetWindowPos($consoleHandle, [AvivNativeWindow]::HWND_BOTTOM, 1300, 900, 420, 180, 0x0040) | Out-Null
  }

  $classConsoleHandle = [AvivNativeWindow]::FindWindow("ConsoleWindowClass", $null)
  if ($classConsoleHandle -ne [IntPtr]::Zero -and $classConsoleHandle -ne $consoleHandle) {
    Write-Host "Moving ConsoleWindowClass window $classConsoleHandle out of capture ($Stage)."
    [AvivNativeWindow]::ShowWindow($classConsoleHandle, 1) | Out-Null
    [AvivNativeWindow]::SetWindowPos($classConsoleHandle, [AvivNativeWindow]::HWND_BOTTOM, 1300, 900, 420, 180, 0x0040) | Out-Null
  }

  $runnerWindows = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and ($_.MainWindowTitle -like "*HostedComputeAgent*" -or $_.MainWindowTitle -like "*hosted-compute-agent*") }
  foreach ($runnerWindow in $runnerWindows) {
    Write-Host "Moving runner window $($runnerWindow.Id) '$($runnerWindow.MainWindowTitle)' handle $($runnerWindow.MainWindowHandle) out of capture ($Stage)."
    [AvivNativeWindow]::ShowWindow($runnerWindow.MainWindowHandle, 1) | Out-Null
    [AvivNativeWindow]::SetWindowPos($runnerWindow.MainWindowHandle, [AvivNativeWindow]::HWND_BOTTOM, 1300, 900, 420, 180, 0x0040) | Out-Null
  }
}

function Write-AvivProcesses {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  Write-Host "Aviv processes ${Label}:"
  $appProcesses = @(Get-Process -Name "Aviv.Windows.App" -ErrorAction SilentlyContinue)
  if ($appProcesses.Count -eq 0) {
    Write-Host "  none"
    return
  }

  foreach ($appProcess in $appProcesses) {
    $appProcess.Refresh()
    Write-Host "  pid=$($appProcess.Id) hasExited=$($appProcess.HasExited) mainWindow=$($appProcess.MainWindowHandle) title='$($appProcess.MainWindowTitle)'"
    [AvivNativeWindow]::DescribeTopLevelWindows($appProcess.Id) | ForEach-Object { Write-Host "    $_" }
  }
}

$env:AVIV_DIAGNOSTIC_LOG = $DiagnosticLog
Remove-Item Env:AVIV_UI_VERIFY -ErrorAction SilentlyContinue
$env:AVIV_SAFE_EDITOR = "1"
Move-BlockingWindowsOutOfCapture "before app launch"
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

  Write-Host "Process-owned top-level windows after launch:"
  [AvivNativeWindow]::DescribeTopLevelWindows($process.Id) | ForEach-Object { Write-Host "  $_" }
  $bestHandle = [AvivNativeWindow]::FindLargestVisibleWindow($process.Id)
  if ($bestHandle -ne [IntPtr]::Zero -and $bestHandle -ne $handle) {
    Write-Host "Switching Aviv capture handle from $handle to enumerated visible window $bestHandle."
    $handle = $bestHandle
  }

  Save-FixedScreenCapture $ImmediateScreenshot "immediate after-launch UI"
  Set-Clipboard -Value $fixture
  [System.Windows.Forms.SendKeys]::SendWait("^a")
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Milliseconds 800
  Save-FixedScreenCapture $LaunchScreenshot "after-launch UI"
  $process.Refresh()
  if ($process.HasExited) {
    Write-Host "Aviv process after launch capture: HasExited=True ExitCode=$($process.ExitCode)"
  }
  else {
    Write-Host "Aviv process after launch capture: HasExited=False"
  }
  Write-AvivProcesses "after launch capture"
  Move-BlockingWindowsOutOfCapture "after launch capture"

  $showResult = [AvivNativeWindow]::ShowWindow($handle, 9)
  $positionResult = [AvivNativeWindow]::SetWindowPos($handle, [AvivNativeWindow]::HWND_TOPMOST, 96, 72, 1160, 760, 0x0040)
  $bringResult = [AvivNativeWindow]::BringWindowToTop($handle)
  $foregroundResult = [AvivNativeWindow]::SetForegroundWindow($handle)
  try {
    [Microsoft.VisualBasic.Interaction]::AppActivate($process.Id)
    Write-Host "AppActivate succeeded for Aviv process $($process.Id)."
  }
  catch {
    Write-Host "AppActivate failed for Aviv process $($process.Id): $($_.Exception.Message)"
  }
  Write-Host "Window activation results: ShowWindow=$showResult SetWindowPos=$positionResult BringWindowToTop=$bringResult SetForegroundWindow=$foregroundResult"
  Start-Sleep -Milliseconds 500
  Write-Host "Process-owned top-level windows after activation:"
  [AvivNativeWindow]::DescribeTopLevelWindows($process.Id) | ForEach-Object { Write-Host "  $_" }
  $titleBuilder = [System.Text.StringBuilder]::new(256)
  [AvivNativeWindow]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity) | Out-Null
  Write-Host "Using Aviv window handle $handle with title '$($titleBuilder.ToString())'"

  Set-Clipboard -Value $fixture
  [System.Windows.Forms.SendKeys]::SendWait("^a")
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait("^v")
  Start-Sleep -Seconds 2
  [AvivNativeWindow]::SetWindowPos($handle, [AvivNativeWindow]::HWND_TOPMOST, 96, 72, 1160, 760, 0x0040) | Out-Null
  try {
    [Microsoft.VisualBasic.Interaction]::AppActivate($process.Id)
  }
  catch {
    Write-Host "Second AppActivate failed for Aviv process $($process.Id): $($_.Exception.Message)"
  }
  [AvivNativeWindow]::BringWindowToTop($handle) | Out-Null
  [AvivNativeWindow]::SetForegroundWindow($handle) | Out-Null
  Start-Sleep -Milliseconds 300
  $process.Refresh()
  if ($process.HasExited) {
    Write-Host "Aviv process before final capture: HasExited=True ExitCode=$($process.ExitCode)"
  }
  else {
    Write-Host "Aviv process before final capture: HasExited=False"
  }
  Write-AvivProcesses "before final capture"
  Write-Host "Capture target before screenshot: $([AvivNativeWindow]::DescribeWindow($handle))"

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
