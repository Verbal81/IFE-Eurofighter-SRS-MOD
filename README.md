# IFE Eurofighter SRS MOD — v1.1m4

## Wichtiger Hinweis / Important Notice

**DE:** Dies ist eine inoffizielle Drittanbieter-Modifikation und steht in keiner Verbindung zu IndiaFoxtEcho bzw. wird nicht von IndiaFoxtEcho unterstützt. Dieser Mod enthält oder verbreitet keine vollständigen originalen IndiaFoxtEcho-Flugzeugdateien. Sämtliche erforderlichen Änderungen werden ausschließlich lokal an der beim Benutzer installierten Eurofighter-Version vorgenommen. IndiaFoxtEcho ist für diese Modifikation nicht verantwortlich und übernimmt keinen Support dafür. Support für diesen Mod erfolgt ausschließlich durch den Mod-Autor.

**EN:** This is an unofficial third-party modification and is not affiliated with or endorsed by IndiaFoxtEcho. This mod does not contain or redistribute complete original IndiaFoxtEcho aircraft files. All required modifications are generated and applied locally to the user's installed Eurofighter files. IndiaFoxtEcho is not responsible for this modification and does not provide support for it. Support for this mod is provided solely by the mod author.

Integration of DCS SimpleRadio Standalone (SRS) with the IndiaFoxtEcho Eurofighter in Microsoft Flight Simulator 2024.

## Compatibility
- Microsoft Flight Simulator 2024
- IndiaFoxtEcho Eurofighter 1.0.10 (verified by exact file hashes)
- DCS SimpleRadio Standalone 2.4.1.0
- Windows PowerShell 5.1, 64-bit

## Installation / Start
1. Close MSFS 2024 and SRS.
2. Run `START_v1.1m4.cmd`.
3. Choose **Einrichtung / Start**.
4. If asked for SRS, select the **CLIENT folder** containing `SR-ClientRadio.exe` directly.
5. SRS and the EF-SRS Bridge start automatically. Connect SRS as usual, then start MSFS 2024.

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
