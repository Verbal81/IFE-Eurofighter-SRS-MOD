$ErrorActionPreference = 'Stop'
$env:PATH = $PSScriptRoot + ';' + $env:PATH
Set-Location -LiteralPath $PSScriptRoot
try {
    [void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'EFSRSBridge.dll'))
    [EFSRSBridge.Entry]::Run()
} catch {
    ($_ | Out-String) | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'bridge-bootstrap.log') -Encoding UTF8
    exit 12
}
