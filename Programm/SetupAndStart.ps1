param([switch]$ChoosePaths,[switch]$CheckOnly)
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
$title='IFE_Eurofighter_SRS_MOD v1.1m4'
$base=Split-Path -Parent $MyInvocation.MyCommand.Path
$data=Join-Path $env:LOCALAPPDATA 'EF-SRS'
$settingsPath=Join-Path $data 'launcher-v11m4-finalrc2.json'
$work=Join-Path $data 'v11m4-finalrc2\profile'
$ps=$windowsPowerShell
function Json([string]$p){ Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function SaveSettings([string]$package,[string]$srs){
    [IO.Directory]::CreateDirectory($data)|Out-Null
    @{package_root=$package;srs_client=$srs}|ConvertTo-Json|Set-Content -LiteralPath $settingsPath -Encoding UTF8
}
function NormalizePackage([string]$p){
    if (-not $p){return ''}
    $p=[IO.Path]::GetFullPath($p).TrimEnd([char[]]'\/')
    if ((Split-Path $p -Leaf) -ieq 'Community') {
        $child=Join-Path $p 'indiafoxtecho-efa'
        if (Test-Path -LiteralPath $child -PathType Container){$p=$child}
    }
    return $p
}
function ValidPackage([string]$p){
    if (-not $p){return $false}
    return (Test-Path -LiteralPath (Join-Path $p 'layout.json') -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $p 'manifest.json') -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $p 'SimObjects\Airplanes\IndiaFoxtEcho_Eurofighter') -PathType Container)
}
function PickFolder([string]$desc,[string]$initial){
    $d=New-Object Windows.Forms.FolderBrowserDialog
    try{$d.Description=$desc;$d.ShowNewFolderButton=$false;if($initial -and (Test-Path -LiteralPath $initial -PathType Container)){$d.SelectedPath=$initial}
        if($d.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){throw 'Ordnerauswahl abgebrochen.'};return $d.SelectedPath
    }finally{$d.Dispose()}
}
function AddInstalledPackagesCandidate($List,[string]$UserCfg){
    if(-not $UserCfg -or -not (Test-Path -LiteralPath $UserCfg -PathType Leaf)){return}
    try{
        foreach($line in Get-Content -LiteralPath $UserCfg -ErrorAction Stop){
            if($line -match '^\s*InstalledPackagesPath\s+"([^"]+)"'){
                $root=[Environment]::ExpandEnvironmentVariables($Matches[1])
                $List.Add((Join-Path $root 'Community\indiafoxtecho-efa'))
                break
            }
        }
    }catch{}
}
function FindPackage {
    $candidates=New-Object System.Collections.Generic.List[string]
    if(Test-Path -LiteralPath $settingsPath){try{$x=Json $settingsPath;if($x.package_root){$candidates.Add([string]$x.package_root)}}catch{}}
    $pkgRoot=Join-Path $env:LOCALAPPDATA 'Packages'
    foreach($d in @(Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter 'Microsoft.Limitless_*' -ErrorAction SilentlyContinue)){
        $candidates.Add((Join-Path $d.FullName 'LocalCache\Packages\Community\indiafoxtecho-efa'))
        AddInstalledPackagesCandidate $candidates (Join-Path $d.FullName 'LocalCache\UserCfg.opt')
    }
    foreach($cfg in @(
        (Join-Path $env:APPDATA 'Microsoft Flight Simulator 2024\UserCfg.opt'),
        (Join-Path $env:APPDATA 'Microsoft Flight Simulator\UserCfg.opt'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft Flight Simulator 2024\UserCfg.opt')
    )){AddInstalledPackagesCandidate $candidates $cfg}
    foreach($p0 in $candidates|Select-Object -Unique){try{$p=NormalizePackage $p0;if(ValidPackage $p){return $p}}catch{}}
    return ''
}
function FindSrs {
    if(Test-Path -LiteralPath $settingsPath){try{$x=Json $settingsPath;if($x.srs_client -and (Test-Path -LiteralPath ([string]$x.srs_client) -PathType Leaf)){return [string]$x.srs_client}}catch{}}
    $roots=@(
        (Join-Path $env:ProgramFiles 'DCS-SimpleRadio-Standalone'),
        (Join-Path ${env:ProgramFiles(x86)} 'DCS-SimpleRadio-Standalone'),
        (Join-Path $env:LOCALAPPDATA 'DCS-SimpleRadio-Standalone')
    )
    foreach($root in $roots){
        foreach($sub in @('CLIENT','Client','client','')){
            $candidate=if($sub){Join-Path (Join-Path $root $sub) 'SR-ClientRadio.exe'}else{Join-Path $root 'SR-ClientRadio.exe'}
            if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}
        }
    }
    return ''
}
try{
    $running=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -match '^(FlightSimulator|FlightSimulator2024|SR-ClientRadio)$'})
    if($running.Count -gt 0){throw 'Bitte MSFS 2024 und SRS komplett schliessen.'}
    $package=FindPackage
    $srs=FindSrs
    if($ChoosePaths -or -not (ValidPackage $package)){
        $picked=PickFolder 'Eurofighter-Ordner indiafoxtecho-efa waehlen. Wenn du versehentlich Community waehlt, wird indiafoxtecho-efa automatisch erkannt.' $package
        $package=NormalizePackage $picked
        if(-not (ValidPackage $package)){throw 'Kein gueltiger indiafoxtecho-efa Paketordner. Bitte NICHT nur Community waehlen, sofern darin indiafoxtecho-efa nicht gefunden wird.'}
    }
    if($ChoosePaths -or -not $srs -or -not (Test-Path -LiteralPath $srs -PathType Leaf)){
        $initialSrs=''
        if($srs){$initialSrs=Split-Path $srs -Parent}
        [void][Windows.Forms.MessageBox]::Show(
            "WICHTIG: Bitte den SRS CLIENT-Ordner waehlen.`r`n`r`nRichtig ist der Ordner, in dem SR-ClientRadio.exe DIREKT liegt.`r`nNicht den uebergeordneten SRS-Hauptordner waehlen.",
            'EF-SRS v1.1m4 - SRS CLIENT-Pfad')
        $dir=PickFolder 'SRS CLIENT-Ordner waehlen - SR-ClientRadio.exe muss DIREKT in diesem Ordner liegen.' $initialSrs
        $candidate=Join-Path $dir 'SR-ClientRadio.exe'
        if(-not (Test-Path -LiteralPath $candidate -PathType Leaf)){
            # Convenience: if the user picked the SRS parent, accept one unambiguous direct child named CLIENT/Client.
            $childCandidates=@(
                (Join-Path $dir 'CLIENT\SR-ClientRadio.exe'),
                (Join-Path $dir 'Client\SR-ClientRadio.exe'),
                (Join-Path $dir 'client\SR-ClientRadio.exe')
            ) | Where-Object {Test-Path -LiteralPath $_ -PathType Leaf} | Select-Object -Unique
            if($childCandidates.Count -eq 1){
                $candidate=$childCandidates[0]
                [void][Windows.Forms.MessageBox]::Show(
                    ("SRS CLIENT automatisch erkannt:`r`n"+(Split-Path $candidate -Parent)),
                    'EF-SRS v1.1m4 - SRS CLIENT erkannt')
            } else {
                throw "Falscher SRS-Ordner.`r`n`r`nBitte den CLIENT-Ordner auswaehlen, in dem SR-ClientRadio.exe DIREKT liegt."
            }
        }
        $srs=$candidate
    }
    SaveSettings $package $srs
    if(Test-Path -LiteralPath $work){Remove-Item -LiteralPath $work -Recurse -Force}
    New-Item -ItemType Directory -Path (Join-Path $work 'payload') -Force|Out-Null
    Copy-Item -LiteralPath (Join-Path $base 'aircraft\Installer.ps1') -Destination (Join-Path $work 'Installer.ps1')
    Copy-Item -LiteralPath (Join-Path $base 'aircraft\manifest.json') -Destination (Join-Path $work 'manifest.json')
    & $ps -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base 'GeneratePayload.ps1') -PackagePath $package -OutputDir (Join-Path $work 'payload') -InstallerManifestPath (Join-Path $work 'manifest.json')
    if($LASTEXITCODE -ne 0){throw 'Semantische Patch-Erzeugung fehlgeschlagen.'}
    $args=@('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $work 'Installer.ps1'),'-PackagePath',$package,'-SrsClientPath',$srs)
    if($CheckOnly){$args+='-CheckOnly'}else{$args+='-InstallOnly'}
    & $ps @args
    if($LASTEXITCODE -ne 0){throw 'Flugzeug-Installation/Vorpruefung wurde abgebrochen.'}
    if($CheckOnly){
        & $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $base 'runtime\Launcher.ps1') -CheckOnly
        if($LASTEXITCODE -ne 0){throw 'Bridge/SRS-Vorpruefung fehlgeschlagen.'}
        [void][Windows.Forms.MessageBox]::Show('Vorpruefung erfolgreich. Nichts gestartet.',$title)
        exit 0
    }
    & $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $base 'DesktopShortcut.ps1')
    if($LASTEXITCODE -ne 0){
        [void][Windows.Forms.MessageBox]::Show('Einrichtung erfolgreich, Desktop-Verknuepfung konnte nicht erstellt werden. Du kannst 2_SRS_MOD_STARTEN.cmd im Mod-Hauptordner verwenden oder unter 3_EINSTELLUNGEN_UND_DEINSTALLATION.cmd die Desktop-Verknuepfung erstellen.',$title)
    }
    & $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $base 'runtime\Launcher.ps1')
    if($LASTEXITCODE -ne 0){throw 'Patch ist eingerichtet, aber Bridge/SRS-Start wurde abgebrochen.'}
}catch{
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,($title+' - Hinweis'))
    exit 1
}
