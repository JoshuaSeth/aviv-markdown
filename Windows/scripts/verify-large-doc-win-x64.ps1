$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot/.."
$Exe = Join-Path $Root "dist/win-x64/Aviv.Windows.App.exe"
$ScreenshotDir = Join-Path $Root "dist/screenshots"
$FixturePath = Join-Path $ScreenshotDir "windows-large-smooth.md"
$Screenshot = Join-Path $ScreenshotDir "windows-large-smooth.png"
$ResultPath = Join-Path $ScreenshotDir "windows-large-smooth-result.json"
$DiagnosticLog = Join-Path $ScreenshotDir "windows-large-smooth.log"

if (!(Test-Path $Exe)) {
  throw "Published executable not found: $Exe"
}

New-Item -ItemType Directory -Force -Path $ScreenshotDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $DiagnosticLog, $ResultPath, $Screenshot

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class AvivLargeDocNative {
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

  [DllImport("user32.dll")]
  public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

  [DllImport("user32.dll")]
  public static extern bool BringWindowToTop(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern bool SetCursorPos(int x, int y);

  [DllImport("user32.dll")]
  private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

  [DllImport("user32.dll")]
  private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

  [DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  [DllImport("user32.dll")]
  private static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll")]
  private static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll")]
  private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

  [DllImport("user32.dll", SetLastError = true)]
  private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

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

  public static bool IsResponsive(IntPtr hWnd, uint timeoutMs) {
    UIntPtr result;
    return SendMessageTimeout(hWnd, 0, UIntPtr.Zero, IntPtr.Zero, 0x0002, timeoutMs, out result) != IntPtr.Zero;
  }

  public static string WindowTitle(IntPtr hWnd) {
    var title = new StringBuilder(256);
    GetWindowText(hWnd, title, title.Capacity);
    return title.ToString();
  }

  public static void LeftClick(int x, int y) {
    SetCursorPos(x, y);
    mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
    mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
  }
}
'@

function New-LargeMarkdownFixture {
  $builder = [System.Text.StringBuilder]::new()
  for ($i = 1; $i -le 240; $i++) {
    [void]$builder.AppendLine("## Azure Smooth Section $i")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("Typing target ${i}:")
    [void]$builder.AppendLine(("a" * 110))
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("This is a large Markdown paragraph with **bold text**, _emphasis_, inline code, [links](https://example.com/$i), and enough normal prose to make the editor do real live markdown work while keeping the document close to a practical report shape.")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("- Item ${i}.1 keeps list formatting active.")
    [void]$builder.AppendLine("- Item ${i}.2 keeps minimap structure active.")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine("| Signal | Status | Owner |")
    [void]$builder.AppendLine("| --- | --- | --- |")
    [void]$builder.AppendLine("| Azure VM | Running | Aviv |")
    [void]$builder.AppendLine()
  }

  return $builder.ToString()
}

function Wait-ForAvivWindow {
  param(
    [Parameter(Mandatory = $true)]
    [System.Diagnostics.Process]$Process,

    [Parameter(Mandatory = $true)]
    [System.Diagnostics.Stopwatch]$Stopwatch
  )

  for ($attempt = 0; $attempt -lt 120; $attempt++) {
    Start-Sleep -Milliseconds 500
    $Process.Refresh()
    if ($Process.HasExited) {
      throw "Aviv exited before exposing a window. ExitCode=$($Process.ExitCode)"
    }

    $handle = [AvivLargeDocNative]::FindLargestVisibleWindow($Process.Id)
    if ($handle -ne [IntPtr]::Zero) {
      return $handle
    }
  }

  throw "Aviv window handle was not available after 60 seconds."
}

function Focus-Editor {
  param(
    [Parameter(Mandatory = $true)]
    [IntPtr]$Handle
  )

  [AvivLargeDocNative]::ShowWindow($Handle, 9) | Out-Null
  [AvivLargeDocNative]::SetWindowPos($Handle, [AvivLargeDocNative]::HWND_TOPMOST, 96, 72, 1160, 760, 0x0040) | Out-Null
  [AvivLargeDocNative]::BringWindowToTop($Handle) | Out-Null
  [AvivLargeDocNative]::SetForegroundWindow($Handle) | Out-Null
  [AvivLargeDocNative]::LeftClick(180, 230)
  Start-Sleep -Milliseconds 200
}

function Save-FixedScreenCapture {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $bitmap = [System.Drawing.Bitmap]::new(1160, 760)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen([System.Drawing.Point]::new(96, 72), [System.Drawing.Point]::Empty, [System.Drawing.Size]::new(1160, 760))
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  }
  finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

Get-Process -Name "Aviv.Windows.App" -ErrorAction SilentlyContinue | Stop-Process -Force
$fixture = New-LargeMarkdownFixture
Set-Content -Path $FixturePath -Value $fixture -Encoding UTF8 -NoNewline

$env:AVIV_DIAGNOSTIC_LOG = $DiagnosticLog
$env:AVIV_SKIP_DEFAULT_APP_PROMPT = "1"
Remove-Item Env:AVIV_UI_VERIFY -ErrorAction SilentlyContinue
Remove-Item Env:AVIV_SAFE_EDITOR -ErrorAction SilentlyContinue

$launchTimer = [System.Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath $Exe -ArgumentList @("`"$FixturePath`"") -PassThru

try {
  $handle = Wait-ForAvivWindow $process $launchTimer
  $launchTimer.Stop()
  Focus-Editor $handle
  [System.Windows.Forms.SendKeys]::SendWait("^{HOME}")
  Start-Sleep -Seconds 2

  $process.Refresh()
  $cpuBefore = $process.TotalProcessorTime
  Start-Sleep -Seconds 5
  $process.Refresh()
  $cpuDeltaSeconds = ($process.TotalProcessorTime - $cpuBefore).TotalSeconds
  $respondingAfterSettle = [AvivLargeDocNative]::IsResponsive($handle, 1000)

  Focus-Editor $handle
  $sendKeyMs = @()
  for ($i = 0; $i -lt 12; $i++) {
    $sendTimer = [System.Diagnostics.Stopwatch]::StartNew()
    [System.Windows.Forms.SendKeys]::SendWait("a")
    $sendTimer.Stop()
    $sendKeyMs += $sendTimer.Elapsed.TotalMilliseconds
    Start-Sleep -Milliseconds 30
  }

  Start-Sleep -Milliseconds 600
  $respondingAfterInput = [AvivLargeDocNative]::IsResponsive($handle, 1000)
  Save-FixedScreenCapture $Screenshot
  $screenshotBytes = (Get-Item $Screenshot).Length

  $averageSendKeysMs = ($sendKeyMs | Measure-Object -Average).Average
  $maxSendKeysMs = ($sendKeyMs | Measure-Object -Maximum).Maximum
  $passed = (
    $fixture.Length -gt 120000 -and
    $launchTimer.Elapsed.TotalMilliseconds -lt 20000 -and
    $cpuDeltaSeconds -lt 2.0 -and
    $respondingAfterSettle -and
    $respondingAfterInput -and
    $averageSendKeysMs -lt 50 -and
    $maxSendKeysMs -lt 250 -and
    $screenshotBytes -gt 10000
  )

  $result = [ordered]@{
    passed = $passed
    largeDocumentBytes = $fixture.Length
    launchMs = [Math]::Round($launchTimer.Elapsed.TotalMilliseconds, 2)
    settleCpuDeltaSecondsOver5s = [Math]::Round($cpuDeltaSeconds, 3)
    respondingAfterSettle = $respondingAfterSettle
    respondingAfterInput = $respondingAfterInput
    averageSendKeysMs = [Math]::Round($averageSendKeysMs, 3)
    maxSendKeysMs = [Math]::Round($maxSendKeysMs, 3)
    screenshotBytes = $screenshotBytes
    screenshot = $Screenshot
    windowTitle = [AvivLargeDocNative]::WindowTitle($handle)
    finishedAt = [DateTimeOffset]::Now.ToString("O")
  }

  $json = $result | ConvertTo-Json -Depth 4
  Set-Content -Path $ResultPath -Value $json -Encoding UTF8
  Write-Host $json

  if (!$passed) {
    throw "Large document responsiveness verification failed. See $ResultPath"
  }
}
finally {
  if (Test-Path $DiagnosticLog) {
    Write-Host "Aviv diagnostic log:"
    Get-Content $DiagnosticLog | ForEach-Object { Write-Host $_ }
  }

  if ($process -and !$process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
