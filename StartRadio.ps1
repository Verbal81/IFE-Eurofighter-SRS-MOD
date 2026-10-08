# Always run UI, COM and the .NET Framework bridge under 64-bit Windows PowerShell.
$windowsDirectory=if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){'Sysnative'}else{'System32'}
$windowsPowerShell=Join-Path $env:SystemRoot ($windowsDirectory+'\WindowsPowerShell\v1.0\powershell.exe')
if(-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)){
    throw '64-Bit Windows PowerShell 5.1 wurde nicht gefunden.'
}
if($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    # These entry points have switch parameters only. Preserve enabled switches.
    $forwardArgs=@()
    foreach($key in $PSBoundParameters.Keys){
        if([bool]$PSBoundParameters[$key]){$forwardArgs+=('-'+$key)}
    }
    & $windowsPowerShell -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath @forwardArgs
    exit $LASTEXITCODE
}
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
$title='IFE_Eurofighter_SRS_MOD - SRS-Mod starten'
$settingsPath=Join-Path $env:LOCALAPPDATA 'EF-SRS\launcher-v11m4-finalrc2.json'
try{
    if(-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)){
        throw 'Bitte zuerst START_v1.1m4.cmd oeffnen und Einmalige Einrichtung / Reparatur ausfuehren.'
    }
    # Daily start: validate the installed state and start SRS/Bridge only.
    # No patch generation, aircraft installation or backup replacement here.
    & $windowsPowerShell -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'runtime\Launcher.ps1')
    exit $LASTEXITCODE
}catch{
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,($title+' - Hinweis'))
    exit 1
}
