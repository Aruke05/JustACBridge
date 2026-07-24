$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'JustACBridge.M5.csproj'
dotnet publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
$exe = Join-Path $PSScriptRoot 'bin\Release\net10.0-windows\win-x64\publish\JustACBridge.M5.exe'
$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$final = Join-Path $dist 'JustACBridge.M5.exe'
try {
    Copy-Item -LiteralPath $exe -Destination $final -Force -ErrorAction Stop
} catch [System.IO.IOException] {
    $version = [version](Get-Item -LiteralPath $exe).VersionInfo.FileVersion
    $final = Join-Path $dist "JustACBridge.M5.v$($version.ToString(3)).exe"
    Copy-Item -LiteralPath $exe -Destination $final -Force
    Write-Warning 'The previous executable is still running. A versioned file was created instead.'
}
Write-Host "Built: $final"
