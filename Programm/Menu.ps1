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
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$ps=$windowsPowerShell
$form=New-Object Windows.Forms.Form
$form.Text='IFE_Eurofighter_SRS_MOD | v1.1m4'
$form.ClientSize=New-Object Drawing.Size(520,660)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$form.Font=New-Object Drawing.Font('Segoe UI',10);$form.BackColor=[Drawing.Color]::FromArgb(24,31,40);$form.ForeColor=[Drawing.Color]::WhiteSmoke
$h=New-Object Windows.Forms.Label;$h.Text='IFE_Eurofighter_SRS_MOD';$h.Font=New-Object Drawing.Font('Segoe UI',15,[Drawing.FontStyle]::Bold);$h.SetBounds(25,20,460,35);$form.Controls.Add($h)
$n=New-Object Windows.Forms.Label;$n.Text="Einrichtung und Verwaltung`r`nZum Fliegen die Desktop-Verknuepfung SRS-Mod starten nutzen.`r`nMSFS und SRS vor diesen Aktionen schliessen.";$n.SetBounds(27,62,465,65);$form.Controls.Add($n)
$actions=@(@('SRS-Mod starten','radio'),@('Einrichtung erneut ausfuehren / Reparatur','start'),@('Flugzeug- oder SRS-Ordner aendern','paths'),@('Installation pruefen (ohne Start)','check'),@('Desktop-Verknuepfung erstellen','shortcut'),@('Bridge beenden','stop'),@('Mod deinstallieren / Flugzeug wiederherstellen','uninstall'))
$script:selected='';$y=140
foreach($a in $actions){$b=New-Object Windows.Forms.Button;$b.Text=$a[0];$b.Tag=$a[1];$b.SetBounds(27,$y,466,48);$b.BackColor=[Drawing.Color]::FromArgb(47,63,78);$b.ForeColor=[Drawing.Color]::White;$b.FlatStyle='Flat';$b.Add_Click({param($s,$e)$script:selected=[string]$s.Tag;$form.Close()});$form.Controls.Add($b);$y+=58}
[void]$form.ShowDialog();$form.Dispose()
if(-not $script:selected){exit 0}
try{
 switch($script:selected){
  'radio' {& $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'StartRadio.ps1')}
  'shortcut' {& $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'DesktopShortcut.ps1');if($LASTEXITCODE -eq 0){[void][Windows.Forms.MessageBox]::Show('Desktop-Verknuepfung SRS-Mod starten wurde erstellt. Den entpackten Mod-Ordner bitte behalten.','IFE_Eurofighter_SRS_MOD')}}
  'start' {& $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SetupAndStart.ps1')}
  'paths' {& $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SetupAndStart.ps1') -ChoosePaths}
  'check' {& $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'SetupAndStart.ps1') -CheckOnly}
  'stop' {& $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'runtime\Launcher.ps1') -StopOnly;[void][Windows.Forms.MessageBox]::Show('Bekannte EF-SRS Bridge-Prozesse wurden gestoppt.','EF-SRS v1.1m4')}
  'uninstall' {& $ps -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Uninstall.ps1')}
 }
 exit $LASTEXITCODE
}catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'EF-SRS v1.1m4 - Fehler');exit 1}
