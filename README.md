<p align="center">
  <img src="https://raw.githubusercontent.com/opencode-ai/opencode-ai/main/logo.png" alt="OpenCode.ai Logo" width="150" />
</p>

# OpenCode Chat Exporter
Automatischer Live-Export deiner [OpenCode](https://opencode.ai) Chat-Sessions als Markdown-Dateien — mit Tray-Icon, Autostart und WPF-GUI.

Kein Token-Verbrauch, keine API-Calls. Das Tool liest direkt aus OpenCodes lokaler SQLite-Datenbank und schreibt jede Session als lesbare `.md`-Datei.

> Tipp: Füge hier gerne einen Screenshot der GUI ein (`docs/screenshot.png`), sobald du das Repo veröffentlichst.

## Warum

OpenCode speichert Chat-Verläufe in einer SQLite-Datenbank ohne eingebauten Markdown-Export. Wenn du deine Chats durchsuchbar, versionierbar oder in einem Wissenssystem (z. B. Obsidian) haben willst, brauchst du sie als Klartext-Dateien.

## Features

- **Live-Watcher** — erkennt Änderungen an der OpenCode-DB automatisch (Polling, konfigurierbares Intervall)
- **Vollständiger Export** — Text, Tool-Calls (Input/Output), Unteragenten (Subtasks), Datei-Anhänge
- **Kein Token-Verbrauch** — reine SQL-Abfragen, kein LLM-Aufruf
- **Tray-Icon** — läuft unauffällig im Hintergrund, kein Taskleisten-Eintrag
- **Autostart** — optional mit Windows starten
- **Einstellungen bleiben erhalten** — gespeichert unter `%APPDATA%\OpenCodeExporter\settings.json`

## Dependencies

Keine npm-/NuGet-Pakete. Nur folgende externe Abhängigkeit:

| Abhängigkeit | Zweck | Installation |
|---|---|---|
| [sqlite3.exe](https://www.sqlite.org/download.html) | Liest OpenCodes SQLite-Datenbank aus | `winget install SQLite.SQLite` |

Alles andere (WPF, WinForms, Registry-Zugriff) ist Teil von Windows/.NET und braucht keine separate Installation.

Nur zum **Kompilieren** als `.exe` zusätzlich nötig:

| Abhängigkeit | Zweck | Installation |
|---|---|---|
| [ps2exe](https://github.com/MScholtes/PS2EXE) | PowerShell-Skript → `.exe` | `Install-Module ps2exe -Scope CurrentUser -Force` |

## Voraussetzungen

- Windows 10/11
- PowerShell 5.1+ (vorinstalliert)

## Installation

### Option A — Direkt als Skript ausführen

```powershell
git clone https://github.com/<dein-user>/opencode-chat-exporter.git
cd opencode-chat-exporter
powershell -ExecutionPolicy Bypass -File .\src\OpenCodeExporter.ps1
```

### Option B — Als .exe kompilieren

```powershell
.\build.ps1
```

Erzeugt `dist\OpenCodeExporter.exe`. Danach einfach starten.

## Benutzung

1. Datenbank-Pfad prüfen (Standard: `%USERPROFILE%\.local\share\opencode\opencode.db`)
2. Ausgabe-Ordner wählen
3. Optional: Reasoning-Export aktivieren, Autostart aktivieren
4. **START** klicken

Jede Session wird als `YYYY-MM-DD_HH-mm_Titel.md` gespeichert und bei Änderungen automatisch aktualisiert.

### Autostart / Tray

- Checkbox "Mit Windows starten" trägt einen Eintrag in `HKCU\...\Run` ein
- Beim Autostart läuft die App direkt minimiert im Tray (kein Fenster, kein Taskleisten-Icon)
- Rechtsklick auf das Tray-Icon: Fenster anzeigen / Start-Stop / Beenden

## Export-Format

```markdown
# Session-Titel

**Datum:** 2026-07-09 14:30
**Session-ID:** `abc123...`

---

### [Du]

Nachricht des Nutzers...

---

### [Assistant]

Antwort...

**[Tool: read] [OK]**
```json
{"filePath": "..."}
```
<details><summary>Output</summary>

​```text
...
​```
</details>
```

## Bekannte Einschränkungen

- Das Tool liest direkt aus OpenCodes internem SQLite-Schema (`session`, `message`, `part` Tabellen). Dieses Schema ist **nicht öffentlich dokumentiert** und kann sich mit neuen OpenCode-Versionen ändern. Falls der Export nach einem OpenCode-Update nicht mehr funktioniert, bitte ein Issue öffnen — das Schema muss dann neu abgeglichen werden.
- Getestet unter Windows mit OpenCode's nativer (nicht WSL-basierter) Installation.
- Bilder/Datei-Anhänge werden nur als Referenz (Dateiname, MIME-Typ) exportiert, nicht als Base64-Daten.

## Mitwirken

Issues und PRs willkommen. Besonders hilfreich: Rückmeldungen wenn sich das OpenCode-DB-Schema ändert.

## Lizenz

LGPL-3.0 — siehe [LICENSE](LICENSE)
