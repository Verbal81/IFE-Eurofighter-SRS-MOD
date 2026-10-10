# MSFS 2020: Testunterstuetzung

Diese Ausgabe ergaenzt die Simulator-Auswahl und passende Suchpfade fuer MSFS 2020. Ein erfolgreicher Flugtest in MSFS 2020 ist noch nicht bestaetigt. Die bisherige MSFS-2024-Auswahl bleibt bei bestehenden Einstellungen erhalten.

## Vorher erforderlich: SimConnect-DLL / kostenloses SDK

**Die benoetigte native 64-Bit-SimConnect-DLL wird nicht mitgeliefert. Wer sie noch nicht hat, muss vor der Mod-Einrichtung das kostenlose FS2020-SDK (Core) installieren.**

1. FS2020 starten und **Optionen → Allgemeine Optionen → Entwickler → Entwicklermodus** einschalten.
2. In der oberen Entwickler-Menueleiste **Help → SDK Installer (Core)** waehlen, herunterladen und installieren.
3. Im gewaehlten SDK-Installationsordner **`SimConnect SDK/lib/SimConnect.dll`** finden, beispielsweise **`C:/MSFS SDK/SimConnect SDK/lib/SimConnect.dll`**.
4. FS2020 wieder schliessen. Diese Datei bei der DLL-Abfrage im Mod waehlen. Nicht die Datei **`Microsoft.FlightSimulator.SimConnect.dll`** aus dem managed-Unterordner waehlen.

[Offizielle SDK-Anleitung](https://docs.flightsimulator.com/html/Introduction/SDK_Overview.htm). Die DLL-Auswahl wird gespeichert; das SDK muss nicht vor jedem Flug gestartet werden. Fuer FS2024 ist normalerweise kein SDK erforderlich.

## Einrichtung

1. Aktuelles ZIP vollstaendig in einen neuen dauerhaften Ordner entpacken. Den gesamten Ordner behalten.
2. MSFS 2020, MSFS 2024 und SRS schliessen.
3. Bei neuer Einrichtung `1_EINMALIG_EINRICHTEN.cmd` starten und **MSFS 2020 (Testunterstuetzung)** waehlen.
4. Falls bereits eine MSFS-2024-Einrichtung existiert: `3_EINSTELLUNGEN_UND_DEINSTALLATION.cmd` starten und **Simulator, Flugzeug- oder SRS-Ordner aendern** waehlen. Dort MSFS 2020 und dessen eigenen Eurofighter-Ordner auswaehlen.
5. Bei Bedarf den SRS-CLIENT-Ordner mit `SR-ClientRadio.exe` auswaehlen. Weiterhin wird SRS 2.4.1.0 benoetigt.
6. Falls die native SimConnect-DLL nicht automatisch gefunden wird, die Datei `SimConnect_internal.dll` oder `SimConnect.dll` aus der eigenen FS2020-Installation waehlen. Alternativ kann die native 64-Bit-Datei aus dem FS2020-SDK verwendet werden: `SimConnect SDK/lib/SimConnect.dll`. Keine DLL aus FS2024 und nicht `Microsoft.FlightSimulator.SimConnect.dll` waehlen. Die Auswahl wird fuer den taeglichen Start gespeichert.
7. Auf die Bereitschaftsmeldung warten, SRS verbinden und danach MSFS 2020 starten.

## Taeglicher Start und Wechsel

Wie bisher **SRS-Mod starten** auf dem Desktop oder `2_SRS_MOD_STARTEN.cmd` verwenden. Die zuletzt eingerichtete Simulator-Auswahl gilt auch fuer diesen Start. Es gibt derzeit ein gemeinsames Einstellungsprofil: Fuer einen Wechsel zwischen 2020 und 2024 erneut ueber Datei 3 die Simulator- und Flugzeugpfade waehlen. Die Einrichtung waehlt nicht automatisch nach dem laufenden Spiel; beide Simulatoren muessen dabei geschlossen sein.

## Dateien und Teststatus

Die bereitgestellten drei XML-Dateien der Version 1.0.10 stimmen exakt mit dem bereits bekannten **gepatchten** 1.0.10-Dateiprofil ueberein. Es wurde kein neues, ungeprueftes XML-Patch-Rezept hinzugefuegt. Fuer die Patch-Erzeugung benoetigt die Einrichtung wie bisher bekannte IFE-Originaldateien oder ihre verifizierte lokale Originalsicherung. Gepatchte Dateien allein ersetzen diese Originalsicherung nicht. Keine IFE-XML-Dateien oder Microsoft-DLLs werden mit dem Mod verteilt.

Die sechsseitige PDF beginnt mit der FS2020-SDK-Vorbereitung; die folgenden fuenf Seiten beschreiben die bisherige FS2024-Bedienung. Diese Zusatzanleitung beschreibt die neue FS2020-Auswahl.

Fuer den praktischen Test: UHF1 und UHF2 im Cockpit aendern und die Uebernahme in SRS pruefen; Lautstaerke, aktives Radio, ENC und HOLD pruefen; danach Simulator/SRS/Bridge beenden und einen erneuten Start ueber die Desktop-Verknuepfung pruefen. Bei Fehlern die vollstaendige Meldung sowie `%LOCALAPPDATA%/EF-SRS/launcher-v11m4-finalrc2-runtime.log` schicken. Eine erfolgreiche Vorpruefung allein bestaetigt noch keinen Funkbetrieb in FS2020.
