param([Parameter(Mandatory=$true)][string]$PackagePath,[Parameter(Mandatory=$true)][string]$OutputDir,[string]$InstallerManifestPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Base=Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest=Get-Content -LiteralPath (Join-Path $Base 'patch_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Aircraft=[IO.Path]::GetFullPath($PackagePath).TrimEnd([char[]]'\/')
function Sha256([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}
function ShaBytes([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace("-","").ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Split-LinesPreserve([byte[]]$Bytes) {
    $text=[Text.Encoding]::UTF8.GetString($Bytes)
    $matches=[regex]::Matches($text, '([^\r\n]*)(\r\n|\n|\r|$)')
    $list=New-Object System.Collections.ArrayList
    foreach($m in $matches) {
        if ($m.Value.Length -eq 0) { continue }
        [void]$list.Add([pscustomobject]@{ Text=$m.Groups[1].Value; Eol=$m.Groups[2].Value })
    }
    return $list
}
function Join-LinesPreserve($Records) {
    $sb=New-Object Text.StringBuilder
    foreach($r in $Records) { [void]$sb.Append($r.Text); [void]$sb.Append($r.Eol) }
    [Text.Encoding]::UTF8.GetBytes($sb.ToString())
}
function Get-NormalizedLines([byte[]]$Bytes) {
    if ($Bytes.Length -ge 3 -and $Bytes[0]-eq 0xEF -and $Bytes[1]-eq 0xBB -and $Bytes[2]-eq 0xBF) {
        $Bytes=$Bytes[3..($Bytes.Length-1)]
    }
    $text=[Text.Encoding]::UTF8.GetString($Bytes)
    return [regex]::Split($text, "\r\n|\n|\r")
}
function Build-LFFile($Lines, [bool]$Bom, [bool]$FinalNewline) {
    $text=[string]::Join("`n", [string[]]$Lines)
    if ($FinalNewline) { $text += "`n" }
    $body=[Text.Encoding]::UTF8.GetBytes($text)
    if (-not $Bom) { return $body }
    $out=New-Object byte[] ($body.Length+3)
    $out[0]=0xEF; $out[1]=0xBB; $out[2]=0xBF
    [Array]::Copy($body,0,$out,3,$body.Length)
    return $out
}

$rel=[ordered]@{
    "EFA_interior.xml"="SimObjects\Airplanes\IndiaFoxtEcho_Eurofighter\model\EFA_interior.xml"
    "EF2000DEP.xml"="SimObjects\Airplanes\IndiaFoxtEcho_Eurofighter\panel\EF2000_MFD\EF2000DEP.xml"
    "EF2000_DEP_Control.xml"="SimObjects\Airplanes\IndiaFoxtEcho_Eurofighter\panel\EF2000_MFD\EF2000_DEP_Control.xml"
}


# Select one verified three-file profile by content, independent of package version.
$liveHashes=@{}
foreach($name in $rel.Keys){
    $p=Join-Path $Aircraft $rel[$name]
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw "Eurofighter-Datei fehlt: $p"}
    $liveHashes[$name]=Sha256 $p
}
$matchingProfiles=@()
foreach($candidate in @($Manifest.source_profiles)){
    $ok=$true
    foreach($name in $rel.Keys){
        if($liveHashes[$name] -notin @([string]$candidate.supported_source.$name,[string]$candidate.expected_output.$name)){$ok=$false;break}
    }
    if($ok){$matchingProfiles+=$candidate}
}
if($matchingProfiles.Count -ne 1){
    $details=($rel.Keys | ForEach-Object {$_+': '+$liveHashes[$_]}) -join "`r`n"
    throw ("Kein eindeutig unterstuetzter Eurofighter-Dateistand. Geprueft sind kompatible 1.0.9- und 1.0.10-Dateien. Nichts am Flugzeug wurde veraendert.`r`n"+$details)
}
$profile=$matchingProfiles[0]
$Manifest.supported_source=$profile.supported_source
$Manifest.expected_output=$profile.expected_output
Write-Host ('Kompatibilitaetsprofil: '+[string]$profile.id)

# Resolve an exact original source for each target.
# TRUE CLEAN INSTALL: untouched live files from the selected verified profile are used directly.
# MIGRATION: an already patched file requires a verified local original backup.
# No IndiaFoxtEcho aircraft XML is shipped with this mod.
$sourceOriginal=@{}
$backupDirs=New-Object System.Collections.Generic.List[object]
$dataRoot=Join-Path $env:LOCALAPPDATA 'EF-SRS'
foreach($rootDir in @(Get-ChildItem -LiteralPath $dataRoot -Directory -Filter 'backups-*' -ErrorAction SilentlyContinue)) {
    foreach($d in @(Get-ChildItem -LiteralPath $rootDir.FullName -Directory -ErrorAction SilentlyContinue)) {
        $jp=Join-Path $d.FullName 'journal.json'
        if(-not (Test-Path -LiteralPath $jp -PathType Leaf)){continue}
        try{$j=Get-Content -LiteralPath $jp -Raw -Encoding UTF8|ConvertFrom-Json}catch{continue}
        if(-not $j.PSObject.Properties['package_root']){continue}
        if(-not ([string]$j.package_root).TrimEnd([char[]]'\/').Equals($Aircraft,[StringComparison]::OrdinalIgnoreCase)){continue}
        $backupDirs.Add([pscustomobject]@{Directory=$d.FullName;Stamp=$d.LastWriteTimeUtc})
    }
}
foreach($name in $rel.Keys) {
    $live=Join-Path $Aircraft $rel[$name]
    $srcHash=[string]$Manifest.supported_source.$name
    $patchedHash=[string]$Manifest.expected_output.$name
    $liveHash=Sha256 $live
    if($liveHash -eq $srcHash) {
        $sourceOriginal[$name]=$live
        Write-Host ("Patch-Quelle "+$name+": lokal installierte IFE-Originaldatei.")
        continue
    }
    if($liveHash -ne $patchedHash){throw "Unbekannter Dateistand: $name`r`nSHA-256: $liveHash"}
    $found=$null
    foreach($entry in @($backupDirs|Sort-Object Stamp -Descending)) {
        $bp=Join-Path $entry.Directory ('original\'+$rel[$name])
        if((Test-Path -LiteralPath $bp -PathType Leaf) -and (Sha256 $bp) -eq $srcHash){$found=$bp;break}
    }
    if(-not $found){
        throw "Der bereits gepatchte Dateistand von $name wurde erkannt, aber keine verifizierte lokale IFE-Originalsicherung ist vorhanden.`r`nFuer eine Migration bitte zuerst die IFE-Dateien ueber die offizielle Installation wiederherstellen. Eine saubere Erstinstallation auf unterstuetzten IFE-Originaldateien benoetigt keine alte EF-SRS-Sicherung."
    }
    $sourceOriginal[$name]=$found
    Write-Host ("Patch-Quelle "+$name+": verifizierte lokale Originalsicherung.")
}

$outDir=[IO.Path]::GetFullPath($OutputDir)
if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
# ---- EFA_interior.xml: component-scoped callback replacement ----
$efaSrc=[string]$sourceOriginal["EFA_interior.xml"]
$efaBytes=[IO.File]::ReadAllBytes($efaSrc)
$records=New-Object System.Collections.ArrayList
foreach($r in @(Split-LinesPreserve $efaBytes)) {
    [void]$records.Add($r)
}

foreach($op in $Manifest.efa_component_callbacks) {
    $cid=[string]$op.component_id
    $componentPrefix='<Component ID="'+$cid+'"'
    $cs=-1
    for($i=0;$i -lt $records.Count;$i++) {
        if ($records[$i].Text.StartsWith($componentPrefix,[StringComparison]::Ordinal)) { $cs=$i; break }
    }
    if ($cs -lt 0) { throw "Component nicht gefunden: $cid" }

    $cb=-1; $ce=-1
    for($i=$cs;$i -lt [Math]::Min($records.Count,$cs+120);$i++) {
        if ($records[$i].Text -eq "<CallbackCode><Code>") { $cb=$i; break }
    }
    if ($cb -lt 0) { throw "CallbackCode nicht gefunden: $cid" }
    for($i=$cb+1;$i -lt [Math]::Min($records.Count,$cb+150);$i++) {
        if ($records[$i].Text -eq "</Code></CallbackCode>") { $ce=$i; break }
    }
    if ($ce -lt 0) { throw "Callback-Ende nicht gefunden: $cid" }

    for($i=$ce-1;$i -ge $cb;$i--) { $records.RemoveAt($i) }
    $insert=@()
    foreach($line in $op.new_callback_lines) {
        $insert += [pscustomobject]@{Text=[string]$line; Eol="`n"}
    }
    for($i=$insert.Count-1;$i -ge 0;$i--) { $records.Insert($cb,$insert[$i]) }
}
$efaOut=Join-LinesPreserve $records
$efaPath=Join-Path $outDir "EFA_interior.xml"
[IO.File]::WriteAllBytes($efaPath,$efaOut)

# ---- EF2000DEP.xml: exact-source line operations, then LF+BOM output ----
$depSrc=[string]$sourceOriginal["EF2000DEP.xml"]
$depLines=New-Object System.Collections.ArrayList
foreach($x in (Get-NormalizedLines ([IO.File]::ReadAllBytes($depSrc)))) { [void]$depLines.Add([string]$x) }
# Split adds a trailing empty item when source ends in newline; original does not need it for indexed recipe.
if ($depLines.Count -gt 0 -and $depLines[$depLines.Count-1] -eq "") { $depLines.RemoveAt($depLines.Count-1) }
foreach($op in @($Manifest.dep_line_ops | Sort-Object start_line -Descending)) {
    $start=[int]$op.start_line; $del=[int]$op.delete_count
    for($i=0;$i -lt $del;$i++) { $depLines.RemoveAt($start) }
    $ins=@($op.insert_lines)
    for($i=$ins.Count-1;$i -ge 0;$i--) { $depLines.Insert($start,[string]$ins[$i]) }
}
$depOut=Build-LFFile $depLines $true $false
$depPath=Join-Path $outDir "EF2000DEP.xml"
[IO.File]::WriteAllBytes($depPath,$depOut)

# ---- EF2000_DEP_Control.xml ----
$ctlSrc=[string]$sourceOriginal["EF2000_DEP_Control.xml"]
$ctlLines=New-Object System.Collections.ArrayList
foreach($x in (Get-NormalizedLines ([IO.File]::ReadAllBytes($ctlSrc)))) { [void]$ctlLines.Add([string]$x) }
if ($ctlLines.Count -gt 0 -and $ctlLines[$ctlLines.Count-1] -eq "") { $ctlLines.RemoveAt($ctlLines.Count-1) }
foreach($op in @($Manifest.control_line_ops | Sort-Object start_line -Descending)) {
    $start=[int]$op.start_line; $del=[int]$op.delete_count
    for($i=0;$i -lt $del;$i++) { $ctlLines.RemoveAt($start) }
    $ins=@($op.insert_lines)
    for($i=$ins.Count-1;$i -ge 0;$i--) { $ctlLines.Insert($start,[string]$ins[$i]) }
}
$ctlOut=Build-LFFile $ctlLines $true $true
$ctlPath=Join-Path $outDir "EF2000_DEP_Control.xml"
[IO.File]::WriteAllBytes($ctlPath,$ctlOut)


foreach($name in $rel.Keys) {
    $p=Join-Path $outDir $name
    $h=Sha256 $p
    $expected=[string]$Manifest.expected_output.$name
    if ($h -ne $expected) { throw "Semantischer Patch erzeugte falschen Hash: $name`r`n$h`r`nErwartet: $expected" }
}
Write-Host 'Semantischer Patch: 3/3 Ausgabedateien exakt verifiziert.' -ForegroundColor Green

# Use the same selected profile for the installer, never a fixed output hash.
if($InstallerManifestPath){
    $installerManifest=Get-Content -LiteralPath (Join-Path $Base 'aircraft\manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($target in $installerManifest.targets){
        $name=[IO.Path]::GetFileName(([string]$target.path).Replace('/','\'))
        if(-not $rel.Contains($name)){throw 'Unbekanntes Ziel im Installer-Manifest.'}
        $target.sha256=[string]$profile.expected_output.$name
        $target.accepted_sha256=@([string]$profile.supported_source.$name,[string]$profile.expected_output.$name)
    }
    $installerManifest.version='1.1m4 - '+[string]$profile.id
    $installerManifest.package_version=[string]$profile.supported_source.ife_version
    $utf8NoBom=New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($InstallerManifestPath),($installerManifest | ConvertTo-Json -Depth 20),$utf8NoBom)
}

