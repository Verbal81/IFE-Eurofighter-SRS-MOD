param([switch]$Remove)
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
$desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
if(-not $desktop -or -not (Test-Path -LiteralPath $desktop -PathType Container)){
    throw 'Desktop-Ordner nicht gefunden. 2_SRS_MOD_STARTEN.cmd kann direkt gestartet werden.'
}
$shortcutPath=Join-Path $desktop 'SRS-Mod starten.lnk'
$scriptPath=Join-Path $PSScriptRoot 'StartRadio.ps1'
$powershell=$windowsPowerShell
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
               ([string]$link.Arguments -match '^-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "[^"]+\\StartRadio\.ps1"$')
        # An update may retarget our own shortcut. Uninstall only removes this folder's link.
        if($Remove -and ([string]$link.Arguments -ne $arguments)){exit 0}
        if(-not $owned){
            if($Remove){exit 0}
            throw 'SRS-Mod starten.lnk gehoert zu einem anderen Programm. Bitte diese Verknuepfung selbst umbenennen oder entfernen und erneut versuchen.'
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
