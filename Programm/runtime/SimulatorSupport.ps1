# Shared simulator selection and path rules. No simulator binaries are shipped.
function GetSimulatorId($Settings) {
    if ($Settings -and $Settings.PSObject.Properties['simulator']) {
        $id = [string]$Settings.simulator
        if ($id -notin @('2020','2024')) { throw 'Unbekannte Simulator-Auswahl. Bitte unter Datei 3 die Pfade neu waehlen.' }
        return $id
    }
    # Preserve existing MSFS 2024 installations when upgrading old settings.
    return '2024'
}
function GetSimulatorSpec([string]$Id) {
    switch ($Id) {
        '2020' { return [pscustomobject]@{
            Id='2020'; Label='MSFS 2020'; AppPattern='Microsoft.FlightSimulator*'; PackagePattern='Microsoft.FlightSimulator_*'
            SteamFolders=@('MicrosoftFlightSimulator','Microsoft Flight Simulator')
            RoamingFolders=@('Microsoft Flight Simulator'); LocalFolders=@('Microsoft Flight Simulator')
        } }
        '2024' { return [pscustomobject]@{
            Id='2024'; Label='MSFS 2024'; AppPattern='Microsoft.Limitless*'; PackagePattern='Microsoft.Limitless_*'
            SteamFolders=@('MicrosoftFlightSimulator2024','Microsoft Flight Simulator 2024')
            RoamingFolders=@('Microsoft Flight Simulator 2024'); LocalFolders=@('Microsoft Flight Simulator 2024')
        } }
        default { throw 'Unterstuetzt werden MSFS 2020 und MSFS 2024.' }
    }
}
function GetSimConnectCandidates([string]$Simulator, [string[]]$AppRoots, [string[]]$SteamLibraries) {
    $spec = GetSimulatorSpec $Simulator
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in $AppRoots) {
        if ($root) {
            foreach ($dll in @('SimConnect_internal.dll','SimConnect.dll')) {
                $paths.Add((Join-Path $root $dll))
            }
        }
    }
    foreach ($library in $SteamLibraries) {
        if ($library) {
            foreach ($game in $spec.SteamFolders) {
                foreach ($dll in @('SimConnect_internal.dll','SimConnect.dll')) {
                    $paths.Add((Join-Path $library ('steamapps\common\'+$game+'\'+$dll)))
                }
            }
        }
    }
    return @($paths | Select-Object -Unique)
}
function TestNativeSimConnect([string]$Path) {
    # Reject x86 and managed wrappers before copying or starting the bridge.
    # Native export/runtime availability is still checked when the bridge connects.
    try {
        if ([IO.Path]::GetFileName($Path) -notin @('SimConnect.dll','SimConnect_internal.dll')) { return $false }
        $b = [IO.File]::ReadAllBytes($Path)
        if ($b.Length -lt 64 -or $b[0] -ne 0x4d -or $b[1] -ne 0x5a) { return $false }
        $pe = [BitConverter]::ToInt32($b,60)
        if ($pe -lt 64 -or $pe -gt ($b.Length-264)) { return $false }
        if ([BitConverter]::ToUInt32($b,$pe) -ne 0x4550 -or
            [BitConverter]::ToUInt16($b,$pe+4) -ne 0x8664 -or
            [BitConverter]::ToUInt16($b,$pe+24) -ne 0x20b -or
            ([BitConverter]::ToUInt16($b,$pe+22) -band 0x2000) -eq 0) { return $false }
        # PE32+ CLR runtime header (directory 14) must be absent in the native DLL.
        if ([BitConverter]::ToUInt32($b,$pe+24+112+14*8) -ne 0) { return $false }
        return $true
    } catch { return $false }
}

function TestSimConnectCandidate([string]$Path, [string]$Simulator) {
    if ($Simulator -eq '2024') {
        # Retain the established FS2024 lookup contract. An extra generic PE/CLR
        # heuristic must not reject the installed internal simulator library.
        # Readability/hash is checked by the caller; Windows resolves exports
        # when the bridge actually loads the user's own DLL.
        return [IO.File]::Exists($Path)
    }
    if ($Simulator -eq '2020') { return (TestNativeSimConnect $Path) }
    throw 'Unbekannte Simulator-Auswahl.'
}
