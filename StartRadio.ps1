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
    & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'runtime\Launcher.ps1')
    exit $LASTEXITCODE
}catch{
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,($title+' - Hinweis'))
    exit 1
}
