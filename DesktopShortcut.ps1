param([switch]$Remove)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
if(-not $desktop -or -not (Test-Path -LiteralPath $desktop -PathType Container)){
    throw 'Desktop-Ordner nicht gefunden. SRS_STARTEN.cmd kann direkt gestartet werden.'
}
$shortcutPath=Join-Path $desktop 'SRS-Mod starten.lnk'
$scriptPath=Join-Path $PSScriptRoot 'StartRadio.ps1'
$powershell=Join-Path $PSHOME 'powershell.exe'
$arguments='-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "'+$scriptPath+'"'
$description='IFE_Eurofighter_SRS_MOD - SRS und Bridge starten'
$shell=$null;$link=$null
try{
    if($Remove -and -not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)){exit 0}
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($shortcutPath)
    if(Test-Path -LiteralPath $shortcutPath){
        # Do not overwrite/remove an unrelated shortcut or one owned by another folder.
        $owned=([string]$link.Description -eq $description) -and
               ([string]$link.TargetPath -ieq $powershell) -and
               ([string]$link.Arguments -eq $arguments)
        if(-not $owned){
            if($Remove){exit 0}
            throw 'SRS-Mod starten.lnk existiert bereits fuer einen anderen Ordner oder ein anderes Programm. Bitte diese Verknuepfung selbst umbenennen oder entfernen und erneut versuchen.'
        }
    }
    if($Remove){Remove-Item -LiteralPath $shortcutPath -Force;exit 0}
    if(-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)){
        throw 'StartRadio.ps1 fehlt. Bitte das komplette Paket entpacken.'
    }
    $link.TargetPath=$powershell
    $link.Arguments=$arguments
    $link.WorkingDirectory=$PSScriptRoot
    $link.Description=$description
    $link.IconLocation=$powershell+',0'
    $link.WindowStyle=1
    $link.Save()
    Write-Host ('Desktop-Verknuepfung erstellt: '+$shortcutPath)
}catch{Write-Error $_;exit 1}
finally{
    if($null -ne $link){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)}
    if($null -ne $shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
}
