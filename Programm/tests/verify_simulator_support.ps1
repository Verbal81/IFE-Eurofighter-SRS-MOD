# Run with 64-bit Windows PowerShell 5.1. Uses disposable fake DLL headers only.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=Split-Path -Parent $PSScriptRoot
foreach($relative in @('SetupAndStart.ps1','Menu.ps1','runtime\Launcher.ps1','runtime\SimulatorSupport.ps1')){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$errors)
    if(@($errors).Count -gt 0){throw ($relative+': '+($errors -join '; '))}
}
. (Join-Path $root 'runtime\SimulatorSupport.ps1')
function Assert([bool]$ok,[string]$message){if(-not $ok){throw $message}}
Assert ((GetSimulatorId ([pscustomobject]@{package_root='old'})) -eq '2024') 'Legacy settings must retain MSFS 2024.'
Assert ((GetSimulatorId ([pscustomobject]@{simulator='2020'})) -eq '2020') 'MSFS 2020 setting lost.'
$rejected=$false
try{[void](GetSimulatorId ([pscustomobject]@{simulator='unknown'}))}catch{$rejected=$true}
Assert $rejected 'Unknown simulator was accepted.'
$paths20=@(GetSimConnectCandidates '2020' @('C:\Apps\2020') @('D:\Steam Library'))
$paths24=@(GetSimConnectCandidates '2024' @('C:\Apps\2024') @('D:\Steam Library'))
Assert ($paths20 -contains 'D:\Steam Library\steamapps\common\MicrosoftFlightSimulator\SimConnect.dll') 'MSFS 2020 Steam path missing.'
Assert ($paths24 -contains 'D:\Steam Library\steamapps\common\MicrosoftFlightSimulator2024\SimConnect_internal.dll') 'MSFS 2024 Steam path missing.'
Assert (-not @($paths20|Where-Object{$_ -like '*MicrosoftFlightSimulator2024*'}).Count) '2020 search crosses into 2024.'
Assert (-not @($paths24|Where-Object{$_ -like '*\MicrosoftFlightSimulator\*'}).Count) '2024 search crosses into 2020.'
Assert ((GetSimulatorSpec '2020').PackagePattern -eq 'Microsoft.FlightSimulator_*') '2020 Store path missing.'
Assert ((GetSimulatorSpec '2024').PackagePattern -eq 'Microsoft.Limitless_*') '2024 Store path changed.'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('efsrs-sim-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
try{
    $dll=Join-Path $temp 'SimConnect.dll'
    $b=New-Object byte[] 512
    $b[0]=0x4d;$b[1]=0x5a
    [BitConverter]::GetBytes([int]64).CopyTo($b,60)
    [BitConverter]::GetBytes([uint32]0x4550).CopyTo($b,64)
    [BitConverter]::GetBytes([uint16]0x8664).CopyTo($b,68)
    [BitConverter]::GetBytes([uint16]0x2000).CopyTo($b,86)
    [BitConverter]::GetBytes([uint16]0x20b).CopyTo($b,88)
    [IO.File]::WriteAllBytes($dll,$b)
    Assert (TestNativeSimConnect $dll) 'Native x64 header rejected.'
    [BitConverter]::GetBytes([uint16]0x14c).CopyTo($b,68)
    [IO.File]::WriteAllBytes($dll,$b)
    Assert (-not (TestNativeSimConnect $dll)) 'x86 DLL accepted.'
    [BitConverter]::GetBytes([uint16]0x8664).CopyTo($b,68)
    [BitConverter]::GetBytes([uint32]1).CopyTo($b,312)
    [IO.File]::WriteAllBytes($dll,$b)
    Assert (-not (TestNativeSimConnect $dll)) 'Managed wrapper accepted.'
    [IO.File]::WriteAllText($dll,'not a DLL')
    Assert (-not (TestNativeSimConnect $dll)) 'Invalid DLL accepted.'
    Assert (TestSimConnectCandidate $dll '2024') 'Established MSFS 2024 lookup was incorrectly gated by new PE checks.'
    Assert (-not (TestSimConnectCandidate $dll '2020')) 'MSFS 2020 native check was bypassed.'
    Assert (-not (TestSimConnectCandidate (Join-Path $temp 'missing.dll') '2024')) 'Missing MSFS 2024 DLL accepted.'
    Assert (-not (TestNativeSimConnect (Join-Path $temp 'missing.dll'))) 'Missing DLL accepted.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
Write-Host 'Simulator settings, separated paths, x64/native checks and PowerShell parsing passed.'
Write-Host 'This does not validate a running simulator or aircraft radio behavior.'
