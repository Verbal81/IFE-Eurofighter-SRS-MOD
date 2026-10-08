# IFE Eurofighter SRS MOD — v1.1m4

## Wichtiger Hinweis / Important Notice

**DE:** Dies ist eine inoffizielle Drittanbieter-Modifikation und steht in keiner Verbindung zu IndiaFoxtEcho bzw. wird nicht von IndiaFoxtEcho unterstützt. Dieser Mod enthält oder verbreitet keine vollständigen originalen IndiaFoxtEcho-Flugzeugdateien. Sämtliche erforderlichen Änderungen werden ausschließlich lokal an der beim Benutzer installierten Eurofighter-Version vorgenommen. IndiaFoxtEcho ist für diese Modifikation nicht verantwortlich und übernimmt keinen Support dafür. Support für diesen Mod erfolgt ausschließlich durch den Mod-Autor.

**EN:** This is an unofficial third-party modification and is not affiliated with or endorsed by IndiaFoxtEcho. This mod does not contain or redistribute complete original IndiaFoxtEcho aircraft files. All required modifications are generated and applied locally to the user's installed Eurofighter files. IndiaFoxtEcho is not responsible for this modification and does not provide support for it. Support for this mod is provided solely by the mod author.

Integration of DCS SimpleRadio Standalone (SRS) with the IndiaFoxtEcho Eurofighter in Microsoft Flight Simulator 2024.

<img width="374" height="768" alt="IFE Eurofighter SRS MOD" src="https://github.com/user-attachments/assets/865d3fab-7adc-4aff-8c8a-db75a44ad72d" />

## Antivirus verification / Security note

The v1.1m3 release package was submitted to the Avira Virus Lab for analysis.

Avira classified the submitted files as **Clean**.

The application is not commercially code-signed, so Windows or other antivirus products may still show reputation-based warnings.

This independent malware analysis is provided as an additional transparency measure.

Users should never disable their antivirus software to install the MOD.


## Compatibility
- Microsoft Flight Simulator 2024
- IndiaFoxtEcho Eurofighter 1.0.10 (verified by exact file hashes)
- DCS SimpleRadio Standalone 2.4.1.0
- Windows PowerShell 5.1, 64-bit

## Einmalige Einrichtung / First-time setup

1. ZIP vollstaendig in einen dauerhaften Ordner entpacken. Diesen Ordner danach
   behalten; die Desktop-Verknuepfung verweist darauf.
2. MSFS 2024 und SRS schliessen.
3. `START_v1.1m4.cmd` starten und **Einmalige Einrichtung / Reparatur** waehlen.
4. Bei der SRS-Auswahl den **CLIENT-Ordner** waehlen, der
   `SR-ClientRadio.exe` direkt enthaelt.
5. Nach erfolgreicher Einrichtung wird **SRS-Mod starten** auf dem Desktop
   angelegt. SRS und Bridge werden gestartet. Auf die Bereitschaftsmeldung
   warten, SRS verbinden und danach MSFS 2024 starten.

**Bereits eingerichtet?** Das aktuelle Paket vollstaendig entpacken, das Menue
oeffnen und **Desktop-Verknuepfung erstellen** waehlen. Eine erneute
Flugzeuginstallation ist dafuer nicht erforderlich. Eine vorhandene Verknuepfung
aus einem anderen Mod-Ordner wird nicht automatisch ueberschrieben; bei einem
Umzug die alte Verknuepfung selbst entfernen und neu erstellen.

**Teststand:** Die neue Desktop-Verknuepfung und der Direktstart muessen noch unter Windows praktisch geprueft werden. Die bestehende Flugzeug- und Funklogik bleibt unveraendert.

## Taeglicher Start / Daily start

Nach einem PC-Neustart oder nach dem Beenden von SRS/Bridge:
1. MSFS 2024 und SRS muessen geschlossen sein.
2. Auf **SRS-Mod starten** auf dem Desktop doppelklicken.
3. Auf die Bereitschaftsmeldung warten, SRS verbinden, dann MSFS starten.

Der Direktstart oeffnet kein Einrichtungsmenue und veraendert keine
Flugzeugdateien. Er prueft den installierten Patch und startet SRS mit der
ENC/HOLD-Erweiterung sowie die Bridge. Das Bereitschaftsfenster bleibt erhalten.
Ohne laufende Bridge werden Frequenzen nicht synchronisiert.

Als Alternative funktioniert `SRS_STARTEN.cmd` im entpackten Mod-Ordner.
Pfadwechsel, Reparatur und Deinstallation bleiben ueber `START_v1.1m4.cmd`
erreichbar. Es wird kein Windows-Autostart eingerichtet.

**EN:** Extract the entire package to a permanent folder and keep that folder.
Run `START_v1.1m4.cmd` once and select **Einmalige Einrichtung / Reparatur**.
Successful setup creates the **SRS-Mod starten** desktop shortcut. Existing
users can select **Desktop-Verknuepfung erstellen** without reinstalling the
aircraft patch. After restarting the PC or closing SRS/Bridge, close MSFS and
SRS, double-click the shortcut, wait for the ready message, connect SRS, then
start MSFS. Daily start does not run the installer or modify aircraft files.
Use `SRS_STARTEN.cmd` as a fallback. Keep the extracted folder in place; if
moving it, remove the old shortcut yourself and recreate it. No Windows
autostart is installed.

The installer verifies the supported aircraft state before writing anything. It creates a local verified backup and uses transactional replacement with rollback.

The mod does not ship Microsoft SimConnect DLLs. It uses `SimConnect_internal.dll` from the user's own installed Microsoft Flight Simulator 2024 copy.

## Deinstallation / Uninstall
Close MSFS 2024 and SRS, run `START_v1.1m4.cmd`, then choose **Deinstallieren / IFE wiederherstellen**.

The uninstaller restores the three supported IFE XML files and `layout.json` from a verified local original backup and verifies the restored hashes. Unknown third-party file states cause a safe abort instead of being overwritten.

## Validated release path
The complete release cycle was successfully verified:

**IFE original state → clean installation → SRS/Bridge startup → MSFS 2024 cockpit/SRS operation → uninstall → verified IFE original state**

Validated functions include UHF1/UHF2, frequency synchronization, volume, active radio, ENC/HOLD and SRS synchronization.

No v1.1m3 runtime is required and no MSFS SDK installation is required.

## License / Lizenz

**By Verbal (GitHub: Verbal81).**

**DE:** Für Veröffentlichungen unter der neuen [Lizenz](LICENSE) ab dem
8. Oktober 2026 sind private, nichtkommerzielle Nutzung und private Änderungen
kostenlos erlaubt, einschließlich nichtkommerzieller Multiplayer-Sitzungen.
Verkauf, kommerzielle Nutzung, Weiterverbreitung (auch kostenlos) und
Veröffentlichung veränderter Versionen benötigen vorherige schriftliche
Erlaubnis. Links zum offiziellen Repository dürfen geteilt werden.
Dies ist eine eigene Lizenz mit einsehbarem Quellcode, keine Open-Source-Lizenz.
Rechte an zuvor gültig unter MIT veröffentlichten Kopien bleiben bestehen;
die neue Lizenz untersagt deren zuvor erlaubten Verkauf nicht rückwirkend.
Für Fremdmaterial gelten dessen eigene Bedingungen; siehe
[THIRD_PARTY_NOTICE.txt](THIRD_PARTY_NOTICE.txt). Maßgeblich ist der vollständige
englische Lizenztext.

**EN:** Distributions under the new [license](LICENSE) from 8 October 2026
permit free private, non-commercial use and private modifications, including
non-commercial multiplayer simulator sessions. Sale, commercial use,
redistribution (including free redistribution), and publication of modified
versions require prior written permission. Sharing links to the official
repository is allowed. This is a custom source-available license, not an
open-source license. Previously valid MIT permissions remain intact; this
change does not retroactively prohibit sale of earlier MIT-licensed copies.
Third-party material remains governed by its own terms. See
[THIRD_PARTY_NOTICE.txt](THIRD_PARTY_NOTICE.txt) and the full license for details.
