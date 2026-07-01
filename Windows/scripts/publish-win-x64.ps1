$ErrorActionPreference = "Stop"

$Root = Resolve-Path "$PSScriptRoot/.."
$Project = Join-Path $Root "src/Aviv.Windows.App/Aviv.Windows.App.csproj"
$Output = Join-Path $Root "dist/win-x64"

dotnet publish $Project `
  -c Release `
  -r win-x64 `
  --self-contained true `
  -p:WindowsPackageType=None `
  -p:WindowsAppSDKSelfContained=true `
  -o $Output

Write-Host "Published Aviv Windows x64 to $Output"
