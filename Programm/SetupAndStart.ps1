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
. (Join-Path $base 'runtime\SimulatorSupport.ps1')
$simulator='2024'
$savedSettings=$null
function Json([string]$p){ Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function SaveSettings([string]$package,[string]$srs,[string]$simulator){
    [IO.Directory]::CreateDirectory($data)|Out-Null
    $values=@{package_root=$package;srs_client=$srs;simulator=$simulator}
    if($savedSettings -and (GetSimulatorId $savedSettings) -eq $simulator -and $savedSettings.PSObject.Properties['simconnect_path']){
        $values.simconnect_path=[string]$savedSettings.simconnect_path
    }
    $values|ConvertTo-Json|Set-Content -LiteralPath $settingsPath -Encoding UTF8
}
function PickSimulator([string]$initial){
    $form=New-Object Windows.Forms.Form
    try{
        $form.Text='EF-SRS - Simulator waehlen'
        $form.Width=430;$form.Height=180;$form.StartPosition='CenterScreen'
        $form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false
        $label=New-Object Windows.Forms.Label
        $label.Text='Welchen Simulator moechtest du einrichten?';$label.SetBounds(15,15,390,25)
        $combo=New-Object Windows.Forms.ComboBox
        $combo.DropDownStyle='DropDownList';$combo.SetBounds(15,45,380,25)
        [void]$combo.Items.Add('MSFS 2024');[void]$combo.Items.Add('MSFS 2020 (Testunterstuetzung)')
        $combo.SelectedIndex=if($initial -eq '2020'){1}else{0}
        $ok=New-Object Windows.Forms.Button
        $ok.Text='Weiter';$ok.SetBounds(295,85,100,30);$ok.DialogResult=[Windows.Forms.DialogResult]::OK
        $form.Controls.AddRange(@($label,$combo,$ok));$form.AcceptButton=$ok
        if($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){throw 'Simulator-Auswahl abgebrochen.'}
        if($combo.SelectedIndex -eq 1){return '2020'}else{return '2024'}
    }finally{$form.Dispose()}
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
    $spec=GetSimulatorSpec $simulator
    $candidates=New-Object System.Collections.Generic.List[string]
    if($savedSettings -and (GetSimulatorId $savedSettings) -eq $simulator -and $savedSettings.PSObject.Properties['package_root']){
        $candidates.Add([string]$savedSettings.package_root)
    }
    $pkgRoot=Join-Path $env:LOCALAPPDATA 'Packages'
    foreach($d in @(Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter $spec.PackagePattern -ErrorAction SilentlyContinue)){
        $candidates.Add((Join-Path $d.FullName 'LocalCache\Packages\Community\indiafoxtecho-efa'))
        AddInstalledPackagesCandidate $candidates (Join-Path $d.FullName 'LocalCache\UserCfg.opt')
    }
    foreach($name in $spec.RoamingFolders){AddInstalledPackagesCandidate $candidates (Join-Path $env:APPDATA ($name+'\UserCfg.opt'))}
    foreach($name in $spec.LocalFolders){AddInstalledPackagesCandidate $candidates (Join-Path $env:LOCALAPPDATA ($name+'\UserCfg.opt'))}
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
    if($running.Count -gt 0){throw 'Bitte MSFS 2020 / 2024 und SRS komplett schliessen.'}
    if(Test-Path -LiteralPath $settingsPath){$savedSettings=Json $settingsPath}
    if($savedSettings){$simulator=GetSimulatorId $savedSettings}
    if($ChoosePaths -or -not $savedSettings){$simulator=PickSimulator $simulator}
    $spec=GetSimulatorSpec $simulator
    Write-Host ('Ausgewaehlter Simulator: '+$spec.Label)
    if($simulator -eq '2020'){
        $simConnectReady=$false
        if($savedSettings -and (GetSimulatorId $savedSettings) -eq '2020' -and $savedSettings.PSObject.Properties['simconnect_path']){
            $simConnectReady=TestNativeSimConnect ([string]$savedSettings.simconnect_path)
        }
        if(-not $simConnectReady){
            $answer=[Windows.Forms.MessageBox]::Show(
                "FS2020 benoetigt eine native 64-Bit-SimConnect-DLL. Sie ist nicht im Mod enthalten.`r`n`r`nFalls die DLL noch fehlt, zuerst das kostenlose FS2020-SDK (Core) installieren:`r`nFS2020 -> Optionen -> Allgemeine Optionen -> Entwickler -> Entwicklermodus.`r`nOben Help -> SDK Installer (Core).`r`n`r`nBenoetigte Datei im SDK-Ordner:`r`nSimConnect SDK\lib\SimConnect.dll`r`nBeispiel: C:\MSFS SDK\SimConnect SDK\lib\SimConnect.dll`r`n`r`nNicht Microsoft.FlightSimulator.SimConnect.dll waehlen.`r`nFS2020 vor der Mod-Einrichtung wieder schliessen.`r`n`r`nDLL vorhanden: OK zum Fortfahren.`r`nDLL fehlt: Abbrechen, SDK installieren, Einrichtung erneut starten.`r`nWeitere Hilfe: FS2020_TESTANLEITUNG.md im Mod-Ordner.",
                'FS2020 - Vorbereitung vor der Installation',
                [Windows.Forms.MessageBoxButtons]::OKCancel,
                [Windows.Forms.MessageBoxIcon]::Information)
            if($answer -ne [Windows.Forms.DialogResult]::OK){throw 'Einrichtung abgebrochen. Bitte zuerst die FS2020-SimConnect-DLL bereitstellen. Es wurde kein neuer Flugzeug-Patch installiert.'}
        }
    }
    $package=FindPackage
    $srs=FindSrs
    if($ChoosePaths -or -not (ValidPackage $package)){
        $picked=PickFolder ($spec.Label+': Eurofighter-Ordner indiafoxtecho-efa waehlen. Community wird ebenfalls erkannt.') $package
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
    SaveSettings $package $srs $simulator
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
