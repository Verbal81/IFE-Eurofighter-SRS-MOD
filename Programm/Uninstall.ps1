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
$title='IFE_Eurofighter_SRS_MOD v1.1m4 - Uninstall'
$base=Split-Path -Parent $MyInvocation.MyCommand.Path
$data=Join-Path $env:LOCALAPPDATA 'EF-SRS'
$settingsPath=Join-Path $data 'launcher-v11m4-finalrc2.json'
$manifest=Get-Content -LiteralPath (Join-Path $base 'patch_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Json([string]$p){Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json}
$rel=[ordered]@{
 'EFA_interior.xml'='SimObjects\Airplanes\IndiaFoxtEcho_Eurofighter\model\EFA_interior.xml'
 'EF2000DEP.xml'='SimObjects\Airplanes\IndiaFoxtEcho_Eurofighter\panel\EF2000_MFD\EF2000DEP.xml'
 'EF2000_DEP_Control.xml'='SimObjects\Airplanes\IndiaFoxtEcho_Eurofighter\panel\EF2000_MFD\EF2000_DEP_Control.xml'
}
try{
    $running=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -match '^(FlightSimulator|FlightSimulator2024|SR-ClientRadio)$'})
    if($running.Count -gt 0){throw 'Bitte MSFS 2024 und SRS komplett schliessen.'}
    if(-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)){throw 'v1.1m4 Einstellungen fehlen. Bitte zuerst 1_EINMALIG_EINRICHTEN.cmd im Mod-Hauptordner ausfuehren.'}
    $package=[IO.Path]::GetFullPath([string](Json $settingsPath).package_root).TrimEnd([char[]]'\/')
    # Stop our/legacy known bridge if present.
    & $windowsPowerShell -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $base 'runtime\Launcher.ps1') -StopOnly
    if($LASTEXITCODE -ne 0){throw 'Bridge konnte nicht sicher beendet werden.'}
    $chosen=$null;$journal=$null
    $all=New-Object System.Collections.Generic.List[object]
    foreach($root in @(Get-ChildItem -LiteralPath $data -Directory -Filter 'backups-*' -ErrorAction SilentlyContinue)){
        foreach($d in @(Get-ChildItem -LiteralPath $root.FullName -Directory -ErrorAction SilentlyContinue)){
            $all.Add([pscustomobject]@{Directory=$d.FullName;Stamp=$d.LastWriteTimeUtc})
        }
    }
    foreach($entry in @($all|Sort-Object Stamp -Descending)){
        $d=$entry.Directory
        $jp=Join-Path $d 'journal.json';if(-not(Test-Path -LiteralPath $jp -PathType Leaf)){continue}
        try{$j=Json $jp}catch{continue}
        if(-not $j.PSObject.Properties['package_root']){continue}
        if(-not ([string]$j.package_root).TrimEnd([char[]]'\/').Equals($package,[StringComparison]::OrdinalIgnoreCase)){continue}
        $ok=$true
        foreach($name in $rel.Keys){$bp=Join-Path $d ('original\'+$rel[$name]);if(-not(Test-Path -LiteralPath $bp -PathType Leaf) -or (Hash $bp) -ne [string]$manifest.supported_source.$name){$ok=$false;break}}
        $layoutBackup=Join-Path $d 'original\layout.json'
        if($ok -and (Test-Path -LiteralPath $layoutBackup -PathType Leaf)){$chosen=$d;$journal=$j;break}
    }
    if(-not $chosen){throw 'Keine verifizierte IFE-1.0.10-Originalsicherung gefunden. Nichts wurde veraendert.'}
    foreach($name in $rel.Keys){
        $live=Join-Path $package $rel[$name];$h=Hash $live;$src=[string]$manifest.supported_source.$name;$patched=[string]$manifest.expected_output.$name
        if($h -ne $src -and $h -ne $patched){throw "Fremde/unbekannte Aenderung erkannt: $name`r`nSHA-256: $h`r`nUninstall sicher abgebrochen."}
    }
    $answer=[Windows.Forms.MessageBox]::Show("IFE-Originaldateien wiederherstellen und EF-SRS v1.1m4 entfernen?`r`n`r`nEine zusaetzliche Sicherheitskopie des aktuellen Standes wird vorher angelegt.",$title,[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Question)
    if($answer -ne [Windows.Forms.DialogResult]::Yes){exit 0}
    $safe=Join-Path $data ('uninstall-safety-v11m4-finalrc2\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $safe -Force|Out-Null
    foreach($name in $rel.Keys){Copy-Item -LiteralPath (Join-Path $package $rel[$name]) -Destination (Join-Path $safe $name) -Force}
    Copy-Item -LiteralPath (Join-Path $package 'layout.json') -Destination (Join-Path $safe 'layout.json') -Force
    # Restore from the immutable original snapshot. Journal paths use '/', while Windows
    # target paths may use '\'. Normalize before matching (fixes the RC-N uninstall bug).
    $records=@{}
    foreach($rec in @($journal.files)){
        $n=(([string]$rec.path) -replace '\\','/').TrimStart('/')
        $records[$n]=$rec
    }
    foreach($path in @($rel.Values)+@('layout.json')){
        $n=($path -replace '\\','/').TrimStart('/')
        if(-not $records.ContainsKey($n)){throw "Sicherungsjournal unvollstaendig: $n"}
        $rec=$records[$n]
        $src=Join-Path (Join-Path $chosen 'original') ($n.Replace('/','\'))
        $dst=Join-Path $package ($n.Replace('/','\'))
        if((Hash $src) -ne [string]$rec.original_sha256){throw "Originalsicherung beschaedigt: $n"}
        Copy-Item -LiteralPath $src -Destination $dst -Force
        [IO.File]::SetLastWriteTimeUtc($dst,[DateTime]::FromFileTimeUtc([long]([string]$rec.original_filetime)))
        if((Hash $dst) -ne [string]$rec.original_sha256){throw "Wiederherstellung nicht verifiziert: $n"}
    }
    foreach($name in $rel.Keys){if((Hash (Join-Path $package $rel[$name])) -ne [string]$manifest.supported_source.$name){throw "IFE-Originalhash nach Uninstall falsch: $name"}}
    foreach($p in @((Join-Path $data 'runtime-v11m4-finalrc2'),(Join-Path $data 'v11m4-finalrc2'))){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop}}
    & $windowsPowerShell -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $base 'DesktopShortcut.ps1') -Remove
    if($LASTEXITCODE -ne 0){Write-Warning 'Desktop-Verknuepfung konnte nicht entfernt werden; bitte bei Bedarf manuell entfernen.'}
    foreach($p in @($settingsPath,(Join-Path $data 'launcher-v11m4-finalrc2.log'),(Join-Path $data 'launcher-v11m4-finalrc2-runtime.log'))){if(Test-Path -LiteralPath $p -PathType Leaf){Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}}
    [void][Windows.Forms.MessageBox]::Show("EF-SRS v1.1m4 deinstalliert.`r`nDie drei IFE-XML-Dateien und layout.json wurden aus der verifizierten Originalsicherung wiederhergestellt.`r`n`r`nSicherheitskopie: $safe",$title)
}catch{
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,($title+' - Sicherer Abbruch'))
    exit 1
}
