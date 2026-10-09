# Requires Windows PowerShell 5.1 (64 bit). Aircraft-only patch; existing SRS
# and bridge binaries/configuration are retained. No automatic elevation.
param([string]$PackagePath, [string]$SrsClientPath, [switch]$Restore, [switch]$CheckOnly, [switch]$InstallOnly, [switch]$RecoverOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
$version = 'IFE_Eurofighter_SRS_MOD v1.1m4 - Installation'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$culture = [Globalization.CultureInfo]::InvariantCulture
$dataRoot = Join-Path $env:LOCALAPPDATA 'EF-SRS'
$backupsRoot = Join-Path $dataRoot 'backups-v11m4-finalrc2'
$settingsPath = Join-Path $dataRoot 'launcher-v11m4-finalrc2.json'
$logPath = Join-Path $dataRoot 'launcher-v11m4-finalrc2.log'
$installMutex = $null
$hasMutex = $false
$transaction = $null
$transactionDirectory = $null
$pendingTemps = New-Object 'System.Collections.Generic.List[string]'
$createdBridge = $null
$allowedPaths = @(
 'SimObjects/Airplanes/IndiaFoxtEcho_Eurofighter/model/EFA_interior.xml',
 'SimObjects/Airplanes/IndiaFoxtEcho_Eurofighter/panel/EF2000_MFD/EF2000DEP.xml',
 'SimObjects/Airplanes/IndiaFoxtEcho_Eurofighter/panel/EF2000_MFD/EF2000_DEP_Control.xml'
)

function Log([string]$Message) {
    Write-Host $Message
    if (-not $CheckOnly) {
        [IO.Directory]::CreateDirectory($dataRoot) | Out-Null
        [IO.File]::AppendAllText($logPath, [DateTime]::UtcNow.ToString('o') + ' ' + $Message + "`r`n", $utf8)
    }
}
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function ReadJson([string]$Path) { return [IO.File]::ReadAllText($Path, $utf8) | ConvertFrom-Json }
function AtomicReplace([string]$SourcePath, [string]$DestinationPath) {
    # Windows PowerShell 5.1 can bind $null to an empty string for a .NET
    # string argument. File.Replace rejects that as a backup filename.
    # Supply a real, unique sibling path for every call, including journals.
    $sourceFull = [IO.Path]::GetFullPath($SourcePath)
    $destinationFull = [IO.Path]::GetFullPath($DestinationPath)
    $swapBackup = $destinationFull + '.efsrs-swap-' + [Guid]::NewGuid().ToString('N') + '.bak'
    try {
        [IO.File]::Replace($sourceFull, $destinationFull, $swapBackup)
    } catch {
        throw ('Dateiaustausch fehlgeschlagen: ' + $destinationFull + "`r`n" + $_.Exception.Message)
    }
    # The permanent verified snapshot is retained; this additional per-call
    # backup is disposable only after File.Replace succeeds.
    if ([IO.File]::Exists($swapBackup)) {
        try { [IO.File]::Delete($swapBackup) }
        catch { Log ('Hinweis: temporaere Austausch-Sicherung erhalten: ' + $swapBackup) }
    }
}
function SaveJson([string]$Path, $Object) {
    $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, ($Object | ConvertTo-Json -Depth 30), $utf8)
        if ([IO.File]::Exists($Path)) { AtomicReplace $temp $Path }
        else { [IO.File]::Move($temp, $Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function PickFile([string]$Title, [string]$Filter) {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = $Title; $dialog.Filter = $Filter; $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'Auswahl abgebrochen. Es wurde kein neuer Patch installiert.' }
        return $dialog.FileName
    } finally { $dialog.Dispose() }
}
function AssertXml([string]$Path) {
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try { while ($reader.Read()) {} } finally { $reader.Dispose() }
}
function AssertClosed {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match '^(FlightSimulator|FlightSimulator2024|SR-ClientRadio)$'
    })
    if ($running.Count -gt 0) { throw 'Bitte MSFS 2024 und SRS komplett schliessen und EF-SRS.exe erneut starten. EAM muss vorher nicht manuell getrennt werden.' }
}
function AssertPayloadStructure([string]$Path, [string]$Relative) {
    AssertXml $Path
    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    $document.Load($Path)
    # Call the CLR getter: XML attributes named Name shadow the .Name property
    # in PowerShell (the control gauge has Name="EF2000_MFD_CONTROL").
    $name = [IO.Path]::GetFileName($Relative)
    if ($name -eq 'EF2000DEP.xml') {
        if ($document.DocumentElement.get_Name() -ne 'SimBase.Document' -or $document.DocumentElement.GetAttribute('Type') -ne 'AceXML' -or $document.DocumentElement.GetAttribute('version') -ne '1,0') {
            throw 'DEP-Anzeigedatei unvollstaendig: SimBase.Document/AceXML-Rahmen fehlt.'
        }
        if ($document.SelectNodes('/SimBase.Document/SimGauge.Gauge').Count -ne 1) { throw 'DEP-Anzeigedatei muss genau eine SimGauge.Gauge enthalten.' }
    } elseif ($name -eq 'EFA_interior.xml') {
        if ($document.DocumentElement.get_Name() -ne 'ModelInfo') { throw 'Unerwartetes ModelInfo-Dokument.' }
    } elseif ($name -eq 'EF2000_DEP_Control.xml') {
        if ($document.DocumentElement.get_Name() -ne 'Gauge') { throw 'Unerwartetes DEP-Control-Dokument.' }
    }
}
function ExactTarget([string]$Root, [string]$Relative) {
    if ($Relative -notin ($allowedPaths + @('layout.json'))) { throw ('Unerlaubter Zielpfad: ' + $Relative) }
    # Never search for filenames; only these exact live paths are eligible.
    return Join-Path $Root ($Relative.Replace('/', '\'))
}
function AssertNoReparseBelowRoot([string]$Root, [string]$Path) {
    $relative = $Path.Substring($Root.Length).TrimStart([char[]]'\/')
    $current = $Root
    foreach ($part in $relative.Split([char[]]'\/')) {
        $current = Join-Path $current $part
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw ('Verknuepfung innerhalb des Zielpakets wird nicht geaendert: ' + $current)
        }
    }
}
function CopyVerifiedBytes([string]$Source, [string]$Destination) {
    # Copy content, not source EFS attributes. Files inherit the destination
    # directory's protection. The caller verifies SHA-256 before any commit.
    # CreateNew retains File.Copy(..., false)'s no-overwrite guarantee.
    $inputStream = $null
    $outputStream = $null
    $created = $false
    $complete = $false
    try {
        $inputStream = [IO.File]::Open($Source, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $created = $true
        $inputStream.CopyTo($outputStream)
        $outputStream.Flush($true)
        $outputStream.Dispose()
        $outputStream = $null
        $inputStream.Dispose()
        $inputStream = $null
        $complete = $true
    } catch {
        throw ('Dateikopie fehlgeschlagen.' + "`r`nQuelle: " + $Source + "`r`nZiel: " + $Destination + "`r`n" + $_.Exception.Message)
    } finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($created -and -not $complete -and [IO.File]::Exists($Destination)) {
            try { [IO.File]::Delete($Destination) } catch {}
        }
    }
}
function ReplaceFile([string]$Destination, [string]$Source, [string]$ExpectedCurrentHash, [string]$FileTime) {
    if ((Hash $Destination) -ne $ExpectedCurrentHash) { throw ('Datei wurde zwischenzeitlich geaendert: ' + $Destination) }
    $temp = $Destination + '.efsrs-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $pendingTemps.Add($temp)
    CopyVerifiedBytes $Source $temp
    if ((Hash $temp) -ne (Hash $Source)) { throw ('Kopie konnte nicht verifiziert werden: ' + $Destination) }
    # Check once more immediately before the atomic per-file replacement.
    if ((Hash $Destination) -ne $ExpectedCurrentHash) { throw ('Zieldatei wurde zwischenzeitlich geaendert: ' + $Destination) }
    AtomicReplace $temp $Destination
    [IO.File]::SetLastWriteTimeUtc($Destination, [DateTime]::FromFileTimeUtc([long]::Parse($FileTime, $culture)))
}
function ValidateJournal($Journal, [string]$Directory, [string]$Root) {
    if (-not ([string]$Journal.package_root).Equals($Root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Sicherung gehoert zu einem anderen Flugzeug-Paket.' }
    $records = @($Journal.files)
    if ($records.Count -ne 4) { throw 'Sicherung muss drei XML-Dateien und layout.json enthalten.' }
    $seen = @{}
    foreach ($record in $records) {
        $relative = [string]$record.path
        $destination = ExactTarget $Root $relative
        AssertNoReparseBelowRoot $Root $destination
        if ($seen.ContainsKey($relative)) { throw 'Doppelter Zielpfad in Sicherung.' }; $seen[$relative] = $true
        if ([string]$record.original_sha256 -notmatch '^[a-f0-9]{64}$' -or [string]$record.new_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Ungueltige Sicherungs-Pruefsumme.' }
        $original = Join-Path $Directory ('original/' + $relative)
        if ((Hash $original) -ne $record.original_sha256) { throw ('Sicherung beschaedigt: ' + $relative) }
        $current = Hash $destination
        if ($current -ne $record.original_sha256 -and $current -ne $record.new_sha256) {
            throw ('Wiederherstellung abgebrochen: fremde Aenderung an ' + $relative + '. Sicherung: ' + $Directory)
        }
        [void][DateTime]::FromFileTimeUtc([long]::Parse([string]$record.original_filetime, $culture))
    }
}
function RestoreJournal($Journal, [string]$Directory, [string]$Root) {
    ValidateJournal $Journal $Directory $Root
    $Journal.state = 'restoring'
    SaveJson (Join-Path $Directory 'journal.json') $Journal
    foreach ($record in @($Journal.files)) {
        $destination = ExactTarget $Root ([string]$record.path)
        $original = Join-Path $Directory ('original/' + $record.path)
        $currentHash = Hash $destination
        if ($currentHash -ne $record.original_sha256 -and $currentHash -ne $record.new_sha256) { throw ('Datei waehrend der Wiederherstellung geaendert: ' + $record.path) }
        if ((Hash $original) -ne $record.original_sha256) { throw ('Sicherung waehrend der Wiederherstellung geaendert: ' + $record.path) }
        if ($currentHash -ne $record.original_sha256) {
            ReplaceFile $destination $original $currentHash ([string]$record.original_filetime)
        } elseif ([IO.File]::GetLastWriteTimeUtc($destination).ToFileTimeUtc().ToString($culture) -ne [string]$record.original_filetime) {
            # An interrupted journal update may precede all aircraft writes.
            # Do not rewrite already unchanged files during recovery.
            [IO.File]::SetLastWriteTimeUtc($destination, [DateTime]::FromFileTimeUtc([long]::Parse([string]$record.original_filetime, $culture)))
        }
        if ((Hash $destination) -ne $record.original_sha256) { throw ('Wiederherstellung nicht verifiziert: ' + $record.path) }
        if ([IO.File]::GetLastWriteTimeUtc($destination).ToFileTimeUtc().ToString($culture) -ne [string]$record.original_filetime) { throw ('Zeitstempel nicht wiederhergestellt: ' + $record.path) }
    }
    $Journal.state = 'restored'; SaveJson (Join-Path $Directory 'journal.json') $Journal
    Log ('Vorherigen Stand vollstaendig wiederhergestellt. Sicherung: ' + $Directory)
}
function JournalCandidates([string]$Root) {
    if (-not [IO.Directory]::Exists($backupsRoot)) { return }
    foreach ($directory in Get-ChildItem -LiteralPath $backupsRoot -Directory | Sort-Object Name -Descending) {
        $journalPath = Join-Path $directory.FullName 'journal.json'
        if (-not [IO.File]::Exists($journalPath)) { continue }
        $j = ReadJson $journalPath
        if (([string]$j.package_root).Equals($Root, [StringComparison]::OrdinalIgnoreCase)) {
            [pscustomobject]@{ Journal = $j; Directory = $directory.FullName }
        }
    }
}
function BridgeProcesses([string]$BridgePath) {
    foreach ($p in Get-CimInstance Win32_Process -Filter "Name='powershell.exe'") {
        if ($p.CommandLine -and $p.CommandLine.IndexOf($BridgePath, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $p }
    }
}
function BridgeReady([string]$ReadyPath, $Process) {
    if (-not [IO.File]::Exists($ReadyPath)) { return $false }
    $live = Get-Process -Id $Process.ProcessId -ErrorAction SilentlyContinue
    if (-not $live) { return $false }
    return [IO.File]::GetLastWriteTimeUtc($ReadyPath) -ge $live.StartTime.ToUniversalTime().AddSeconds(-2)
}

try {
    if (-not [Environment]::Is64BitProcess) { throw 'Bitte den Launcher mit 64-Bit Windows PowerShell starten.' }
    $installMutex = New-Object System.Threading.Mutex($false, 'Local\EFSRS_Installer_v11m4')
    $hasMutex = $installMutex.WaitOne(0)
    if (-not $hasMutex) { throw 'Ein EF-SRS-Installer arbeitet bereits. Bitte dieses zweite Fenster schliessen.' }
    AssertClosed
    $saved = $null
    if ([IO.File]::Exists($settingsPath)) { $saved = ReadJson $settingsPath }
    if (-not $PackagePath -and $saved -and $saved.PSObject.Properties['package_root']) { $PackagePath = [string]$saved.package_root }
    if (-not $PackagePath -or -not [IO.File]::Exists((Join-Path $PackagePath 'layout.json'))) {
        $PackagePath = [IO.Path]::GetDirectoryName((PickFile 'layout.json im installierten Eurofighter-Paket auswaehlen' 'layout.json|layout.json'))
    }
    $root = [IO.Path]::GetFullPath($PackagePath).TrimEnd([char[]]'\/')
    $journals = @(JournalCandidates $root)
    $incomplete = @($journals | Where-Object { $_.Journal.state -in @('prepared','committing','restoring') })
    if ($CheckOnly -and $incomplete.Count -gt 0) { throw 'Unvollstaendige Installation gefunden. EF-SRS.exe stellt zuerst den gesicherten Stand wieder her.' }
    foreach ($j in $incomplete) { RestoreJournal $j.Journal $j.Directory $root }
    if ($RecoverOnly) { Log 'Offene Installationsjournale geprueft; abgeschlossene Installationen bleiben erhalten.'; exit 0 }
    if ($Restore) {
        if ($incomplete.Count -eq 0) {
            $last = @($journals | Where-Object { $_.Journal.state -eq 'committed' } | Select-Object -First 1)
            if ($last.Count -eq 0) { throw 'Keine abgeschlossene EF-SRS-Sicherung fuer dieses Paket vorhanden.' }
            RestoreJournal $last[0].Journal $last[0].Directory $root
        }
        [void][System.Windows.Forms.MessageBox]::Show('Der zuletzt gesicherte vorherige Stand wurde wiederhergestellt. SRS und Bridge wurden nicht gestartet.', $version)
        exit 0
    }

    $manifest = ReadJson (Join-Path $PSScriptRoot 'manifest.json')
    if (@($manifest.targets).Count -ne 3 -or @($manifest.targets.path | Sort-Object -Unique).Count -ne 3) { throw 'Patch-Manifest ist unvollstaendig oder mehrdeutig.' }
    $aircraftManifest = ReadJson (Join-Path $root 'manifest.json')
    Log ('Eurofighter-Version: ' + $aircraftManifest.package_version + '; Kompatibilitaet wird anhand aller drei Datei-Pruefsummen geprueft.')
    $layoutPath = Join-Path $root 'layout.json'
    $layoutOriginalHash = Hash $layoutPath
    $layoutOriginalFileTime = [IO.File]::GetLastWriteTimeUtc($layoutPath).ToFileTimeUtc().ToString($culture)
    $layoutBytes = [IO.File]::ReadAllBytes($layoutPath)
    if ((Hash $layoutPath) -ne $layoutOriginalHash) { throw 'layout.json wurde waehrend der Vorpruefung geaendert.' }
    $layoutText = $utf8.GetString($layoutBytes).TrimStart([char]0xFEFF)
    $layout = $layoutText | ConvertFrom-Json
    if (-not $layout.PSObject.Properties['content']) { throw 'layout.json: content fehlt.' }
    $plans = New-Object 'System.Collections.Generic.List[object]'
    $needsInstall = $false
    foreach ($target in $manifest.targets) {
        $relative = [string]$target.path
        $destination = ExactTarget $root $relative
        AssertNoReparseBelowRoot $root $destination
        $expectedPayload = 'payload/' + [IO.Path]::GetFileName($relative)
        if ($target.payload -ne $expectedPayload) { throw 'Ungueltiger Payload-Pfad.' }
        $payload = Join-Path $PSScriptRoot $expectedPayload
        AssertXml $destination; AssertPayloadStructure $payload $relative
        if ([IO.Path]::GetFileName($relative) -eq 'EF2000DEP.xml') {
            $currentDocument = New-Object System.Xml.XmlDocument
            $currentDocument.XmlResolver = $null
            $currentDocument.Load($destination)
            Log ('DEP vor Installation: Root=' + $currentDocument.DocumentElement.get_Name() + '; SHA256=' + (Hash $destination))
        }
        if ((Hash $payload) -ne $target.sha256) { throw ('Payload-Pruefsumme stimmt nicht: ' + $relative) }
        $originalHash = Hash $destination
        if ($originalHash -notin @($target.accepted_sha256)) { throw ('Unbekannter Dateistand: ' + $relative + "`r`nSHA-256: " + $originalHash + "`r`nEs wurde kein neuer Patch installiert.") }
        $entries = @($layout.content | Where-Object { ([string]$_.path).Replace('\','/').Equals($relative, [StringComparison]::OrdinalIgnoreCase) })
        if ($entries.Count -ne 1) { throw ('layout.json: Zielpfad muss genau einmal vorhanden sein: ' + $relative) }
        if ($originalHash -ne $target.sha256 -or [long]$entries[0].size -ne (Get-Item -LiteralPath $destination).Length -or [long]$entries[0].date -ne [IO.File]::GetLastWriteTimeUtc($destination).ToFileTimeUtc()) { $needsInstall = $true }
        $plans.Add([pscustomobject]@{ path=$relative; destination=$destination; source=$payload; original_sha256=$originalHash; new_sha256=[string]$target.sha256; original_filetime=[IO.File]::GetLastWriteTimeUtc($destination).ToFileTimeUtc().ToString($culture); new_filetime=''; new_size=(Get-Item -LiteralPath $payload).Length })
        Log ('Gepruefter Live-Pfad: ' + $relative)
    }
    if (-not $SrsClientPath -and $saved -and $saved.PSObject.Properties['srs_client']) { $SrsClientPath = [string]$saved.srs_client }
    if (-not $SrsClientPath -or -not [IO.File]::Exists($SrsClientPath)) {
        $SrsClientPath = PickFile 'SRS CLIENT-Ordner: SR-ClientRadio.exe auswaehlen (Version 2.4.1.0)' 'SRS-Client|SR-ClientRadio.exe'
    }
    $SrsClientPath = [IO.Path]::GetFullPath($SrsClientPath)
    if ([IO.Path]::GetFileName($SrsClientPath) -ne 'SR-ClientRadio.exe') { throw 'Bitte SR-ClientRadio.exe im SRS CLIENT-Ordner auswaehlen.' }
    $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($SrsClientPath)
    if ($vi.FileMajorPart -ne 2 -or $vi.FileMinorPart -ne 4 -or $vi.FileBuildPart -ne 1 -or $vi.FilePrivatePart -ne 0) { throw ('SRS-Dateiversion ' + $vi.FileVersion + ' wird nicht gestartet. Benoetigt wird 2.4.1.0 im CLIENT-Ordner.') }
    if ($CheckOnly) { Log 'Alle Vorpruefungen bestanden. CheckOnly hat keine Installation ausgefuehrt.'; exit 0 }
    AssertClosed

    # Complete preflight precedes every aircraft write. Each run gets a unique,
    # immutable original snapshot including layout.json and original times.
    if ($needsInstall) {
    $transactionDirectory = Join-Path $backupsRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($transactionDirectory) | Out-Null
    $now = [DateTime]::UtcNow
    foreach ($plan in $plans) {
        $plan.new_filetime = if ($plan.original_sha256 -eq $plan.new_sha256) { $plan.original_filetime } else { $now.ToFileTimeUtc().ToString($culture) }
    }
    $objects = [regex]::Matches($layoutText, '\{[^{}]*\}')
    $replacements = New-Object 'System.Collections.Generic.List[object]'
    foreach ($plan in $plans) {
        $hits = @($objects | Where-Object {
            $entry = $_.Value | ConvertFrom-Json
            $entry.PSObject.Properties['path'] -and ([string]$entry.path).Replace('\','/').Equals($plan.path, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($hits.Count -ne 1) { throw ('Layoutobjekt nicht eindeutig: ' + $plan.path) }
        $entry = $hits[0]
        $value = $entry.Value
        foreach ($field in @('size','date')) {
            $pattern = '("' + $field + '"\s*:\s*)[0-9]+'
            if ([regex]::Matches($value, $pattern).Count -ne 1) { throw ('Layoutfeld nicht eindeutig: ' + $field) }
            $number = if ($field -eq 'size') { $plan.new_size.ToString($culture) } else { $plan.new_filetime }
            $value = [regex]::Replace($value, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($m) $m.Groups[1].Value + $number })
        }
        $replacements.Add([pscustomobject]@{ index=$entry.Index; length=$entry.Length; value=$value })
    }
    foreach ($replacement in $replacements | Sort-Object index -Descending) {
        $layoutText = $layoutText.Substring(0,$replacement.index) + $replacement.value + $layoutText.Substring($replacement.index+$replacement.length)
    }
    [void]($layoutText | ConvertFrom-Json)
    $layoutStage = Join-Path $transactionDirectory 'new-layout.json'
    $newLayoutBytes = $utf8.GetBytes($layoutText)
    if ($layoutBytes.Length -ge 3 -and $layoutBytes[0] -eq 239 -and $layoutBytes[1] -eq 187 -and $layoutBytes[2] -eq 191) { $newLayoutBytes = [byte[]](@(239,187,191) + $newLayoutBytes) }
    [IO.File]::WriteAllBytes($layoutStage, $newLayoutBytes)
    $plans.Add([pscustomobject]@{ path='layout.json'; destination=$layoutPath; source=$layoutStage; original_sha256=$layoutOriginalHash; new_sha256=(Hash $layoutStage); original_filetime=$layoutOriginalFileTime; new_filetime=$now.ToFileTimeUtc().ToString($culture); new_size=$newLayoutBytes.Length })
    foreach ($plan in $plans) {
        if ((Hash $plan.destination) -ne $plan.original_sha256) { throw ('Ziel seit Vorpruefung geaendert: ' + $plan.path) }
        $backup = Join-Path $transactionDirectory ('original/' + $plan.path)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
        CopyVerifiedBytes $plan.destination $backup
        if ((Hash $backup) -ne $plan.original_sha256) { throw ('Sicherung nicht verifiziert: ' + $plan.path) }
    }
    $transaction = [pscustomobject]@{ version=$version; package_root=$root; state='prepared'; files=@($plans | Select-Object -Property @('path', 'original_sha256', 'new_sha256', 'original_filetime', 'new_filetime')) }
    SaveJson (Join-Path $transactionDirectory 'journal.json') $transaction
    $transaction.state = 'committing'; SaveJson (Join-Path $transactionDirectory 'journal.json') $transaction
    foreach ($plan in $plans) {
        if ((Hash $plan.destination) -ne $plan.original_sha256) { throw ('Datei vor Installation zwischenzeitlich geaendert: ' + $plan.path) }
        if ($plan.original_sha256 -ne $plan.new_sha256) { ReplaceFile $plan.destination $plan.source $plan.original_sha256 $plan.new_filetime }
    }
    $verifiedLayout = ReadJson $layoutPath
    foreach ($plan in $plans) {
        if ((Hash $plan.destination) -ne $plan.new_sha256) { throw ('Installierte Datei nicht verifiziert: ' + $plan.path) }
        if ($plan.path -ne 'layout.json') {
            AssertPayloadStructure $plan.destination $plan.path
            $entries = @($verifiedLayout.content | Where-Object { ([string]$_.path).Replace('\','/').Equals($plan.path, [StringComparison]::OrdinalIgnoreCase) })
            if ($entries.Count -ne 1 -or [long]$entries[0].size -ne (Get-Item -LiteralPath $plan.destination).Length -or [long]$entries[0].date -ne [IO.File]::GetLastWriteTimeUtc($plan.destination).ToFileTimeUtc()) { throw ('Layoutmetadaten nicht verifiziert: ' + $plan.path) }
        }
    }
    $transaction.state = 'committed'
    try { SaveJson (Join-Path $transactionDirectory 'journal.json') $transaction }
    catch { $transaction.state = 'committing'; throw }
    Log ('Patch und Layout erfolgreich verifiziert. Sicherung: ' + $transactionDirectory)
    Log 'DEP-Dokumentrahmen nach Installation: SimBase.Document / AceXML / SimGauge.Gauge geprueft.'
    } else { Log 'Der aktuelle Patch und alle drei Layoutmetadaten sind bereits korrekt installiert. Keine erneute Dateiinstallation.' }
    SaveJson $settingsPath ([pscustomobject]@{ package_root=$root; srs_client=$SrsClientPath })

    if ($InstallOnly) { Log 'Flugzeugdateien und Pfade eingerichtet. Der v1.1m4-Launcher uebernimmt den Start.'; exit 0 }

    # Readiness belongs to the existing bridge process, not merely to the patch.
    $ready = Join-Path $runtime 'bridge.ready'
    $existing = @(BridgeProcesses $bridge)
    if ($existing.Count -gt 1) { throw 'Mehrere Bridge-Prozesse gefunden. Patch installiert; bitte Bridge-Prozesse schliessen und EF-SRS.exe erneut starten.' }
    if ($existing.Count -eq 1 -and -not (BridgeReady $ready $existing[0])) { throw 'Vorhandene Bridge ist noch nicht bereit. Patch installiert; bitte Bridge schliessen und EF-SRS.exe erneut starten.' }
    if ($existing.Count -eq 0) {
        if ([IO.File]::Exists($ready)) { [IO.File]::Delete($ready) }
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $createdBridge = Start-Process -FilePath $powershell -WorkingDirectory $runtime -WindowStyle Hidden -ArgumentList @('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"' + $bridge + '"')) -PassThru
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            $createdBridge.Refresh()
            if ($createdBridge.HasExited) { throw ('Bridge beendet: Code ' + $createdBridge.ExitCode + '. Patch installiert; siehe bridge-bootstrap.log und bridge.log in %LOCALAPPDATA%\EF-SRS.') }
            if ([IO.File]::Exists($ready) -and [IO.File]::GetLastWriteTimeUtc($ready) -ge $createdBridge.StartTime.ToUniversalTime().AddSeconds(-2)) { break }
            Start-Sleep -Milliseconds 200
        } while ([DateTime]::UtcNow -lt $deadline)
        $createdBridge.Refresh()
        if ($createdBridge.HasExited -or -not [IO.File]::Exists($ready)) { throw 'Bridge meldet keine Bereitschaft. Patch installiert; bitte Protokolle pruefen. MSFS noch nicht starten.' }
    }
    # No old shortcuts or installation-folder-name guesses are used.
    $srs = Start-Process -FilePath $SrsClientPath -WorkingDirectory ([IO.Path]::GetDirectoryName($SrsClientPath)) -PassThru
    Start-Sleep -Milliseconds 500
    $srs.Refresh()
    if ($srs.HasExited) { throw 'Der ausgewaehlte SRS-Client hat sich sofort beendet. Patch installiert; MSFS noch nicht starten.' }
    if ($createdBridge) {
        $createdBridge.Refresh()
        if ($createdBridge.HasExited) { throw 'Bridge nach dem Start beendet. Patch installiert; MSFS noch nicht starten.' }
    } elseif (-not (BridgeReady $ready $existing[0])) { throw 'Vorhandene Bridge ist nicht mehr bereit. Patch installiert; MSFS noch nicht starten.' }
    Log 'SRS 2.4.1.0 gestartet; Bridge laeuft und wartet auf MSFS.'
    [void][System.Windows.Forms.MessageBox]::Show("EF-SRS ist bereit.`r`nSRS 2.4.1.0 gestartet.`r`nBridge laeuft und wartet auf MSFS.`r`n`r`nIn SRS wie gewohnt Server und EAM verbinden.`r`nDanach kannst du MSFS 2024 starten.", $version)
} catch {
    $message = $_.Exception.Message
    if ($transaction -and $transaction.state -eq 'committed') { $message = "Patch und Layout sind installiert und verifiziert.`r`n" + $message }
    if ($transaction -and $transaction.state -in @('prepared','committing')) {
        try { RestoreJournal $transaction $transactionDirectory $root; $message += "`r`nDer Stand vor diesem Installationsversuch wurde wiederhergestellt." }
        catch { $message += "`r`nWiederherstellung nicht abgeschlossen: " + $_.Exception.Message + "`r`nSicherung: " + $transactionDirectory }
    }
    if ($createdBridge) {
        try { $createdBridge.Refresh(); if (-not $createdBridge.HasExited) { $createdBridge.Kill() } } catch {}
    }
    try { Log ('FEHLER: ' + $message) } catch { Write-Host $message }
    [void][System.Windows.Forms.MessageBox]::Show($message, ($version + ' - Fehler'))
    exit 1
} finally {
    foreach ($temp in $pendingTemps) { if ([IO.File]::Exists($temp)) { try { [IO.File]::Delete($temp) } catch {} } }
    if ($hasMutex) { $installMutex.ReleaseMutex() }
    if ($installMutex) { $installMutex.Dispose() }
}
