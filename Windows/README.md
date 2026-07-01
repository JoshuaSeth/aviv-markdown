# Aviv Windows

This folder contains the native Windows implementation of Aviv.

Requested stack:

- C# / .NET 10
- WinUI 3 via Windows App SDK
- Windows App SDK 2.2.0
- CommunityToolkit.Mvvm 8.4.2
- App target: `net10.0-windows10.0.19041.0`
- Core target: `net10.0`
- Self-contained unpackaged publish for practical client installs

## Structure

```text
Aviv.Windows.slnx
src/Aviv.Windows.Core       Platform-neutral Markdown, command, minimap, and layout parity core
src/Aviv.Windows.App        WinUI 3 native Windows app
tests/Aviv.Windows.Core.Tests
```

## Current Parity Contract

The Windows implementation is being built from the macOS source surface, not as a separate editor:

- Live rendered Markdown in one editable surface
- Active-line syntax reveal without geometry/layout shifts
- Headings, bold, italic, inline code, links, local images, blockquotes, rules, tables, task lists, and fenced code
- Native file open/save/save-as/revert workflow
- Multi-document tabs and native window commands
- Zoom in/out/reset
- Find/replace commands
- Print and page setup commands
- Clean top chrome, status metrics, and minimap viewport sync
- Command parity with the macOS command identifiers

## Verification

Cross-platform core verification runs on macOS and Windows:

```bash
dotnet test Windows/tests/Aviv.Windows.Core.Tests/Aviv.Windows.Core.Tests.csproj
```

The WinUI app restores on macOS, but the WinUI XAML compiler is a Windows executable. App build, runtime, screenshot, and real UI interaction verification must run on Windows.

## Publish

Self-contained unpackaged Windows client builds are produced from Windows PowerShell:

```powershell
Windows/scripts/publish-win-x64.ps1
Windows/scripts/publish-win-arm64.ps1
```
