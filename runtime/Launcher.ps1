param([switch]$CheckOnly, [switch]$StopOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
$title = 'IFE_Eurofighter_SRS_MOD v1.1m4 - Start'
$dataRoot = Join-Path $env:LOCALAPPDATA 'EF-SRS'
$runtimeRoot = Join-Path $dataRoot 'runtime-v11m4-finalrc2'
$logPath = Join-Path $dataRoot 'launcher-v11m4-finalrc2-runtime.log'
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$session = $null
$newBridge = $null
$newSrs = $null
$mutex = $null
$locked = $false

function Log([string]$Text) {
    Write-Host $Text
    [IO.Directory]::CreateDirectory($dataRoot) | Out-Null
    [IO.File]::AppendAllText($logPath, [DateTime]::UtcNow.ToString('o') + ' ' + $Text + "`r`n", $utf8)
}
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Json([string]$Path) { [IO.File]::ReadAllText($Path, $utf8) | ConvertFrom-Json }
function Require([bool]$Ok, [string]$Message) { if (-not $Ok) { throw $Message } }
function ReadSrsBundleRuntime([string]$Exe) {
    # Read only. SRS 2.4.1.0 publish.ps1 uses PublishSingleFile=true.
    # Bundle signature/header format: dotnet/runtime v10.0.0 HostModel/Bundle.
    $stream = [IO.File]::Open($Exe, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = $null
    try {
        $reader = New-Object IO.BinaryReader($stream)
        # The native Windows apphost marker is in the first MiB, before payloads.
        $head = $reader.ReadBytes([int][Math]::Min($stream.Length, 1048576))
        Require ($head.Length -ge 64 -and $head[0] -eq 77 -and $head[1] -eq 90) 'SRS-CLIENT ist keine Windows-EXE.'
        $signature = [byte[]]@(0x8b,0x12,0x02,0xb9,0x6a,0x61,0x20,0x38,0x72,0x7b,0x93,0x02,0x14,0xd7,0xa0,0x32,0x13,0xf5,0xb9,0xe6,0xef,0xae,0x33,0x18,0xee,0x3b,0x2d,0xce,0x24,0xb3,0x6a,0xae)
        $bytesAsText = [Text.Encoding]::GetEncoding(28591)
        $index = $bytesAsText.GetString($head).IndexOf($bytesAsText.GetString($signature), [StringComparison]::Ordinal)
        if ($index -lt 8) { return $null }
        $offset = [BitConverter]::ToInt64($head, $index - 8)
        if ($offset -eq 0) { return $null } # Normal, unbundled .NET apphost.
        Require ($offset -ge ($index + 32) -and $offset -le ($stream.Length - 64)) 'Ungueltiger SRS-Single-File-Header.'
        $stream.Position = $offset
        $major = $reader.ReadUInt32(); $minor = $reader.ReadUInt32(); $count = $reader.ReadInt32()
        Require ($major -eq 6 -and $minor -eq 0 -and $count -gt 0 -and $count -le 10000) 'Unbekanntes SRS-Single-File-Format.'
        # .NET bundle IDs are short UTF-8 strings (one-byte length prefix).
        $idLength = [int]$reader.ReadByte()
        Require ($idLength -ge 1 -and $idLength -le 127) 'Ungueltige SRS-Bundle-Kennung.'
        $bundleId = $utf8.GetString($reader.ReadBytes($idLength))
        Require ($bundleId -match '^[A-Za-z0-9_+\-/]{1,127}$') 'Unbekannte SRS-Bundle-Kennung.'
        [void]$reader.ReadInt64(); [void]$reader.ReadInt64() # deps.json offset/size
        $configOffset = $reader.ReadInt64(); $configSize = $reader.ReadInt64()
        $flags = $reader.ReadUInt64()
        Require ($flags -eq 0) 'Unbekannte SRS-Bundle-Optionen.'
        Require ($configOffset -gt 0 -and $configSize -ge 2 -and $configSize -le 1048576 -and $configOffset -le ($offset - $configSize)) 'Ungueltige eingebettete SRS-Laufzeitkonfiguration.'
        $stream.Position = $configOffset
        $configBytes = $reader.ReadBytes([int]$configSize)
        Require ($configBytes.Length -eq $configSize) 'Eingebettete SRS-Laufzeitkonfiguration ist unvollstaendig.'
        return ($utf8.GetString($configBytes) | ConvertFrom-Json)
    } finally {
        if ($reader) { $reader.Dispose() } else { $stream.Dispose() }
    }
}
function AssertClosed {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(FlightSimulator|FlightSimulator2024|SR-ClientRadio)$' })
    Require ($running.Count -eq 0) 'Bitte MSFS 2024 und SRS komplett schliessen und START.cmd erneut starten.'
}
function BridgeProcesses([bool]$IncludeLegacy) {
    $efRoot = [regex]::Escape((Join-Path $dataRoot 'runtime-v11'))
    # Match only our own EF-SRS runtime session launchers under %LOCALAPPDATA%\EF-SRS.
    $pattern = '(?i)(?:^|\s)-File\s+"?(' + $efRoot + '[^" ]*\\session-[a-f0-9]{32}\\RunBridge\.ps1)(?:"|\s|$)'
    foreach ($process in Get-CimInstance Win32_Process -Filter "Name='powershell.exe'") {
        if ($process.CommandLine -and $process.CommandLine -match $pattern) {
            [pscustomobject]@{ Id=[int]$process.ProcessId; Script=[string]$Matches[1]; CommandLine=[string]$process.CommandLine }
        }
    }
}
function StopKnownBridges([bool]$IncludeLegacy, $Manifest) {
    $found = @(BridgeProcesses $true)
    foreach ($process in $found) {
        $current = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $process.Id) -ErrorAction SilentlyContinue
        if ($current -and $current.CommandLine -eq $process.CommandLine) {
            Log ('Beende vorherige EF-SRS Bridge PID ' + $process.Id + ': ' + $process.Script)
            Stop-Process -Id $process.Id -ErrorAction Stop
            Start-Sleep -Milliseconds 250
            Require (-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) 'Vorherige EF-SRS Bridge konnte nicht beendet werden.'
        }
    }
}
function FindInstalledSimConnect {
    $candidates = New-Object System.Collections.Generic.List[string]

    # Microsoft Store / Xbox package: query the registered app installation, not Carlo-specific paths.
    try {
        $apps=@(Get-AppxPackage -Name 'Microsoft.Limitless*' -ErrorAction SilentlyContinue)
        foreach($app in $apps) {
            if($app.InstallLocation) {
                $candidates.Add((Join-Path ([string]$app.InstallLocation) 'SimConnect_internal.dll'))
            }
        }
    } catch {}

    # Steam default and registered Steam root.
    $steamRoots=New-Object System.Collections.Generic.List[string]
    try {
        $sp=(Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if($sp){$steamRoots.Add([string]$sp)}
    } catch {}
    $steamRoots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam'))
    foreach($steam in $steamRoots | Select-Object -Unique) {
        foreach($game in @('MicrosoftFlightSimulator2024','Microsoft Flight Simulator 2024')) {
            $candidates.Add((Join-Path $steam ('steamapps\common\'+$game+'\SimConnect_internal.dll')))
        }
        $vdf=Join-Path $steam 'steamapps\libraryfolders.vdf'
        if(Test-Path -LiteralPath $vdf -PathType Leaf) {
            try {
                foreach($line in Get-Content -LiteralPath $vdf -ErrorAction Stop) {
                    if($line -match '"path"\s+"([^"]+)"') {
                        $lib=$Matches[1] -replace '\\\\','\'
                        foreach($game in @('MicrosoftFlightSimulator2024','Microsoft Flight Simulator 2024')) {
                            $candidates.Add((Join-Path $lib ('steamapps\common\'+$game+'\SimConnect_internal.dll')))
                        }
                    }
                }
            } catch {}
        }
    }

    foreach($candidate in $candidates | Select-Object -Unique) {
        try {
            if([IO.File]::Exists($candidate)) {
                # Verify we can actually read the user's installed file.
                $h=Hash $candidate
                return [pscustomobject]@{Path=[IO.Path]::GetFullPath($candidate);SHA256=$h;Source='MSFS 2024 installation'}
            }
        } catch {}
    }

    # Manual fallback for custom Steam/Xbox locations.
    [void][Windows.Forms.MessageBox]::Show(
        "SimConnect_internal.dll wurde nicht automatisch gefunden.`r`n`r`nBitte jetzt den MSFS-2024-Installationsordner waehlen (NICHT Community).`r`nDarin muss SimConnect_internal.dll liegen.`r`n`r`nEs wird nur Ihre lokal installierte MSFS-Datei verwendet; sie ist nicht Bestandteil dieses Mods.",
        'EF-SRS v1.1m4 - MSFS 2024 SimConnect')
    $dlg=New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description='MSFS-2024-Installationsordner waehlen - SimConnect_internal.dll muss direkt darin liegen.'
    $dlg.ShowNewFolderButton=$false
    if($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){throw 'MSFS-2024-Installationsordner wurde nicht ausgewaehlt.'}
    $manual=Join-Path $dlg.SelectedPath 'SimConnect_internal.dll'
    Require ([IO.File]::Exists($manual)) 'SimConnect_internal.dll wurde im ausgewaehlten MSFS-2024-Ordner nicht gefunden.'
    return [pscustomobject]@{Path=[IO.Path]::GetFullPath($manual);SHA256=(Hash $manual);Source='manuell gewaehlte MSFS 2024 installation'}
}
function StartScoped([string]$File, [string]$Arguments, [string]$WorkingDirectory, [bool]$Hook, [int]$Radio1, [int]$Radio2) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $File; $start.Arguments = $Arguments; $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.EnvironmentVariables['EFSRS11L_SESSION'] = $session
    $start.EnvironmentVariables['EFSRS11L_TOKEN'] = $token
    $start.EnvironmentVariables['EFSRS11L_RADIO1'] = [string]$Radio1
    $start.EnvironmentVariables['EFSRS11L_RADIO2'] = [string]$Radio2
    if ($Hook) { $start.EnvironmentVariables['DOTNET_STARTUP_HOOKS'] = Join-Path $session 'EFSRSHook.dll' }
    else { $start.CreateNoWindow = $true; $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden }
    return [Diagnostics.Process]::Start($start)
}
function WaitReady($Process, [string]$Name, [int]$Seconds) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $ready = Join-Path $session ($Name + '.ready')
    while ([DateTime]::UtcNow -lt $deadline) {
        $Process.Refresh()
        if($Process.HasExited){
            $detail=''
            $boot=Join-Path $session ($Name + '-bootstrap.log')
            if($Name -eq 'bridge'){$boot=Join-Path $session 'bridge-bootstrap.log'}
            if(Test-Path -LiteralPath $boot){
                $detail += "`r`n`r`nBootstrap:`r`n" + ((Get-Content -LiteralPath $boot -Tail 20 -ErrorAction SilentlyContinue) -join "`r`n")
            }
            $bridgeLog=Join-Path $dataRoot 'bridge.log'
            if($Name -eq 'bridge' -and (Test-Path -LiteralPath $bridgeLog)){
                $detail += "`r`n`r`nBridge-Log (letzte Zeilen):`r`n" + ((Get-Content -LiteralPath $bridgeLog -Tail 12 -ErrorAction SilentlyContinue) -join "`r`n")
            }
            throw ($Name + ' wurde beendet. Protokollordner: ' + $session + $detail)
        }
        $errorFile = Join-Path $session ($Name + '.error')
        if ([IO.File]::Exists($errorFile)) { throw [IO.File]::ReadAllText($errorFile) }
        if ([IO.File]::Exists($ready) -and [IO.File]::ReadAllText($ready).Trim() -eq $token) { return }
        Start-Sleep -Milliseconds 150
    }
    throw ($Name + ' meldet keine Bereitschaft. Protokollordner: ' + $session)
}

try {
    Require ([Environment]::Is64BitProcess) 'Bitte 64-Bit Windows PowerShell verwenden.'
    $mutex = New-Object Threading.Mutex($false, 'Local\EFSRS_Installer_v11m4')
    $locked = $mutex.WaitOne(0)
    Require $locked 'Ein EF-SRS-Launcher arbeitet bereits.'
    AssertClosed
    $manifest = Json (Join-Path $PSScriptRoot 'manifest.json')
    foreach ($property in $manifest.files.PSObject.Properties) {
        Require ((Hash (Join-Path $PSScriptRoot $property.Name)) -eq $property.Value) ('Datei des Release-Kandidaten veraendert: ' + $property.Name)
    }
    if ($StopOnly) {
        StopKnownBridges $true $manifest
        Log 'EF-SRS Bridge beendet.'
        exit 0
    }
    $settingsPath = Join-Path $dataRoot 'launcher-v11m4-finalrc2.json'
    Require ([IO.File]::Exists($settingsPath)) 'v1.1m4-Pfade fehlen. Bitte zuerst Einrichtung / Start oder Pfade neu waehlen.'
    $settings = Json $settingsPath
    $package = [IO.Path]::GetFullPath([string]$settings.package_root)
    $srsExe = [IO.Path]::GetFullPath([string]$settings.srs_client)
    $srsDir = [IO.Path]::GetDirectoryName($srsExe)
    Require ([IO.Path]::GetFileName($srsExe) -ieq 'SR-ClientRadio.exe') 'Gespeicherter SRS-CLIENT-Pfad zeigt nicht auf SR-ClientRadio.exe.'
    $version = [Diagnostics.FileVersionInfo]::GetVersionInfo($srsExe)
    Require (($version.FileMajorPart -eq 2) -and ($version.FileMinorPart -eq 4) -and ($version.FileBuildPart -eq 1) -and ($version.FilePrivatePart -eq 0)) 'Unterstuetzt wird ausschliesslich SRS 2.4.1.0.'
    $srsInputs = @($srsExe)
    $runtimeConfig = ReadSrsBundleRuntime $srsExe
    if ($null -ne $runtimeConfig) {
        Log 'SRS 2.4.1.0 Single-File-CLIENT erkannt. DLL und Laufzeitkonfiguration liegen in der EXE.'
    } else {
        $srsDll = Join-Path $srsDir 'SR-ClientRadio.dll'
        $srsRuntime = Join-Path $srsDir 'SR-ClientRadio.runtimeconfig.json'
        Require ([IO.File]::Exists($srsDll) -and [IO.File]::Exists($srsRuntime)) 'Unbekannter SRS-CLIENT: weder gueltiges Single-File-Bundle noch vollstaendige DLL-Ausgabe. Bitte den CLIENT-Ordner mit SR-ClientRadio.exe verwenden.'
        $assembly = [Reflection.AssemblyName]::GetAssemblyName($srsDll)
        Require ($assembly.Name -eq 'SR-ClientRadio' -and $assembly.Version.ToString() -eq '2.4.1.0') 'Unbekannte SRS-Client-Assembly.'
        $runtimeConfig = Json $srsRuntime
        $srsInputs += @($srsDll, $srsRuntime)
        Log 'SRS 2.4.1.0 CLIENT mit separater DLL erkannt.'
    }
    Require ([string]$runtimeConfig.runtimeOptions.tfm -match '^net10\.0(?:$|-)') 'Unbekannte SRS-Laufzeit; erwartet wird die .NET-10-Ausgabe von 2.4.1.0.'
    $configProperties = $runtimeConfig.runtimeOptions.PSObject.Properties['configProperties']
    if ($configProperties) {
        $supported = $configProperties.Value.PSObject.Properties['System.StartupHookProvider.IsSupported']
        if ($supported) { Require ($supported.Value -ne $false) 'Dieser SRS-Build unterstuetzt keine Laufzeiterweiterung.' }
    }
    Require ([string]::IsNullOrWhiteSpace($env:DOTNET_STARTUP_HOOKS)) 'Eine andere .NET-Start-Erweiterung ist aktiv. Sie wird nicht ueberschrieben.'
    $packageManifest = Json (Join-Path $package 'manifest.json')
    Log ('Eurofighter-Version: ' + $packageManifest.package_version + '; pruefe kompatiblen EF-SRS-Dateistand.')
    $layoutPath = Join-Path $package 'layout.json'
    $layout = Json $layoutPath
    $baseline = @()
    foreach ($target in $manifest.aircraft) {
        $path = Join-Path $package (([string]$target.path).Replace('/', '\'))
        $actualHash = Hash $path
        Require ($actualHash -in @($target.accepted_sha256)) ('Kein unterstuetzter EF-SRS-Dateistand: ' + $target.path)
        $xmlSettings = New-Object Xml.XmlReaderSettings
        $xmlSettings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $xmlSettings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create($path, $xmlSettings)
        try { [void]$reader.MoveToContent(); Require ($reader.Name -eq $target.root) ('Unerwartete XML-Wurzel: ' + $target.path); while ($reader.Read()) {} }
        finally { $reader.Dispose() }
        $entries = @($layout.content | Where-Object { ([string]$_.path).Replace('\','/').Equals([string]$target.path, [StringComparison]::OrdinalIgnoreCase) })
        Require ($entries.Count -eq 1) ('layout.json: Pfad nicht eindeutig: ' + $target.path)
        Require ([long]$entries[0].size -eq (Get-Item -LiteralPath $path).Length -and [long]$entries[0].date -eq [IO.File]::GetLastWriteTimeUtc($path).ToFileTimeUtc()) ('layout.json: Metadaten stimmen nicht: ' + $target.path)
        $baseline += [pscustomobject]@{ path=$path; sha256=$actualHash }
    }
    $baseline += [pscustomobject]@{ path=$layoutPath; sha256=(Hash $layoutPath) }
    $configPath = Join-Path $dataRoot 'EFSRSBridge.ini'
    if (-not [IO.File]::Exists($configPath)) {
        [IO.Directory]::CreateDirectory($dataRoot) | Out-Null
        @('SrsHost=127.0.0.1','SrsPort=9040','Radio1Id=1','Radio2Id=2','SyncBothOnModeOn=true') |
            Set-Content -LiteralPath $configPath -Encoding ASCII
        Log 'Neue lokale Bridge-Konfiguration mit sicheren Standardwerten erstellt.'
    }
    $config = @{ SrsHost='127.0.0.1'; SrsPort='9040'; Radio1Id='1'; Radio2Id='2' }
    foreach ($line in [IO.File]::ReadAllLines($configPath)) {
        if ($line -match '^\s*([^#;=]+?)\s*=\s*(.*?)\s*$') { $config[$Matches[1]] = $Matches[2] }
    }
    Require ($config.SrsHost -in @('127.0.0.1','localhost','::1')) 'Diese Erweiterung benoetigt den lokalen SRS-CLIENT.'
    $radio1 = [int]$config.Radio1Id; $radio2 = [int]$config.Radio2Id
    Require ($radio1 -ge 1 -and $radio1 -le 10 -and $radio2 -ge 1 -and $radio2 -le 10 -and $radio1 -ne $radio2) 'Ungueltige UHF-Zuordnung in EFSRSBridge.ini.'
    $baseline += [pscustomobject]@{ path=$configPath; sha256=(Hash $configPath) }
    foreach ($inputPath in $srsInputs) { $baseline += [pscustomobject]@{ path=$inputPath; sha256=(Hash $inputPath) } }

    $sim = FindInstalledSimConnect
    Log ('SimConnect aus lokal installiertem MSFS 2024: ' + $sim.Path)
    $baseline += [pscustomobject]@{ path=$sim.Path; sha256=$sim.SHA256 }

    $token = [Guid]::NewGuid().ToString('N')
    $session = Join-Path $runtimeRoot ('session-' + $token)
    Require (-not [IO.Directory]::Exists($session)) 'Sitzungsordner existiert bereits.'
    [IO.Directory]::CreateDirectory($session) | Out-Null
    # Local private copy only from the user's own MSFS installation; nothing is shipped in this ZIP.
    Copy-Item -LiteralPath $sim.Path -Destination (Join-Path $session 'SimConnect.dll')
    Require ($sim.SHA256 -eq (Hash (Join-Path $session 'SimConnect.dll'))) 'Lokale SimConnect-Kopie konnte nicht verifiziert werden.'
    $baseline | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $session 'baseline.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RunBridge.ps1') -Destination (Join-Path $session 'RunBridge.ps1')
    Log 'v1.1m4 XML/Layout und SRS-Version geprueft. Verwende SimConnect aus MSFS 2024; kompiliere Bridge + ENC/HOLD ...'
    $hookDll = Join-Path $session 'EFSRSHook.dll'
    Add-Type -Path @((Join-Path $PSScriptRoot 'src\Link.cs'), (Join-Path $PSScriptRoot 'src\SrsHook.cs')) -OutputAssembly $hookDll -OutputType Library
    $hook = [Reflection.Assembly]::LoadFrom($hookDll)
    foreach ($reference in $hook.GetReferencedAssemblies()) { Require ($reference.Name -eq 'mscorlib') ('Unerwartete Hook-Abhaengigkeit: ' + $reference.Name) }
    $tests = $hook.GetType('EFSRSLink.SelfTest', $true).GetMethod('Run')
    Log ([string]$tests.Invoke($null, $null))
    Add-Type -Path @((Join-Path $PSScriptRoot 'src\NativeSimConnect.cs'), (Join-Path $PSScriptRoot 'src\Bridge.cs'), (Join-Path $PSScriptRoot 'src\Link.cs')) -OutputAssembly (Join-Path $session 'EFSRSBridge.dll') -OutputType Library -ReferencedAssemblies @('System.Windows.Forms.dll','System.dll','System.Core.dll')
    foreach ($property in $manifest.files.PSObject.Properties) { Require ((Hash (Join-Path $PSScriptRoot $property.Name)) -eq $property.Value) ('Release-Kandidat wurde waehrend der Kompilierung veraendert: ' + $property.Name) }
    foreach ($item in $baseline) { Require ((Hash $item.path) -eq $item.sha256) ('Datei wurde waehrend der Vorpruefung veraendert: ' + $item.path) }
    if ($CheckOnly) { Log ('Vorpruefung und Kompilierung erfolgreich. Keine Prozesse gestartet oder beendet. Pruefordner: ' + $session); exit 0 }
    AssertClosed
    StopKnownBridges $true $manifest
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $newBridge = StartScoped $powershell ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + (Join-Path $session 'RunBridge.ps1') + '"') $session $false $radio1 $radio2
    WaitReady $newBridge 'bridge' 15
    Log 'Starte SRS mit der sitzungsgebundenen ENC/HOLD-Erweiterung ...'
    $newSrs = StartScoped $srsExe '' $srsDir $true $radio1 $radio2
    WaitReady $newSrs 'hook' 45
    $newBridge.Refresh(); $newSrs.Refresh()
    Require (-not $newBridge.HasExited -and -not $newSrs.HasExited) 'Bridge oder SRS wurde nach dem Start beendet.'
    foreach ($item in $baseline) { Require ((Hash $item.path) -eq $item.sha256) ('Quelldatei wurde unerwartet geaendert: ' + $item.path) }
    Log ('Bereit: v1.1m4 SRS-Erweiterung bestaetigt, Bridge laeuft. Protokollordner: ' + $session)
    [void][Windows.Forms.MessageBox]::Show("SRS und ENC/HOLD-Erweiterung sind gestartet.`r`nBridge wartet auf MSFS.`r`n`r`nJetzt wie gewohnt Server und EAM verbinden, danach MSFS starten.`r`nBitte ENC und die UHF-Anzeige unter HOLD im Cockpit pruefen.", $title)
} catch {
    $message = $_.Exception.Message
    try { Log ($_.Exception.ToString() + "`r`n" + $_.ScriptStackTrace) } catch {}
    if ($session) { $message += "`r`nProtokollordner: " + $session }
    if ($newSrs) { try { $newSrs.Refresh(); if (-not $newSrs.HasExited) { $newSrs.Kill() } } catch {} }
    if ($newBridge) { try { $newBridge.Refresh(); if (-not $newBridge.HasExited) { $newBridge.Kill() } } catch {} }
    try { Log ('FEHLER: ' + $message) } catch { Write-Host $message }
    [void][Windows.Forms.MessageBox]::Show($message, ($title + ' - Fehler'))
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
