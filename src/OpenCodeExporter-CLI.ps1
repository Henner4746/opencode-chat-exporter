# Export-OpenCodeChats.ps1
# Beobachtet die OpenCode SQLite-DB und exportiert jeden Chat als .md
# Kein Token-Verbrauch - nur rohe Datenbankabfragen
#
# Speicherort:      src\OpenCodeExporter-CLI.ps1 (Kommandozeilen-Variante ohne GUI)
# Output-Ordner:    konfigurierbar, siehe $OUTPUT_DIR unten
# Voraussetzung:    sqlite3.exe im PATH (winget install SQLite.SQLite)

# ── Konfiguration ────────────────────────────────────────────────────────────
$DB_PATH           = "%USERPROFILE%\.local\share\opencode\opencode.db"
$OUTPUT_DIR        = "%USERPROFILE%\Documents\OpenCode_Chats"
$POLL_SEC          = 5
$SQLITE            = "sqlite3"
$INCLUDE_REASONING = $false  # $true = reasoning-Blöcke mit exportieren
$TOOL_OUTPUT_MAX   = 2000    # Max. Zeichen für Tool-Output (0 = alles)
# ─────────────────────────────────────────────────────────────────────────────

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] $msg"
}

function Sanitize-Filename($name) {
    $clean = $name -replace '[\\/:*?"<>|]', '_'
    $clean = $clean.Trim()
    if ($clean.Length -gt 80) { $clean = $clean.Substring(0, 80).TrimEnd() }
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "Untitled" }
    return $clean
}

function Truncate-Text($text, $max) {
    if ($max -le 0 -or $text.Length -le $max) { return $text }
    return $text.Substring(0, $max) + "`n... [gekürzt]"
}

function Export-Session($sessionId, $sessionTitle, $sessionCreated) {
    $dateObj  = [DateTimeOffset]::FromUnixTimeMilliseconds($sessionCreated).LocalDateTime
    $dateStr  = $dateObj.ToString("yyyy-MM-dd")
    $timeStr  = $dateObj.ToString("HH-mm")
    $safeName = Sanitize-Filename $sessionTitle
    $filename = "${dateStr}_${timeStr}_${safeName}.md"
    $expOutputDir = [System.Environment]::ExpandEnvironmentVariables($OUTPUT_DIR)
    $outPath  = Join-Path $expOutputDir $filename

    $safeSessionId = $sessionId -replace "'", "''"

    $query = @"
SELECT
    m.time_created AS msg_time,
    json_extract(m.data, '$.role') AS role,
    p.time_created AS part_time,
    p.data         AS part_data
FROM message m
LEFT JOIN part p ON p.message_id = m.id
WHERE m.session_id = '$safeSessionId'
ORDER BY m.time_created ASC, p.time_created ASC;
"@

    $rows = & $SQLITE -separator "|||" $DB_PATH $query 2>$null
    if (-not $rows) { return $false }

    $sb          = [System.Text.StringBuilder]::new()
    $currentRole = $null
    $msgBuffer   = [System.Collections.Generic.List[string]]::new()

    [void]$sb.AppendLine("# $sessionTitle")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Datum:** $($dateObj.ToString('yyyy-MM-dd HH:mm'))")
    [void]$sb.AppendLine("**Session-ID:** ``$sessionId``")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")

    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row)) { continue }
        $cols = $row -split "\|\|\|"
        if ($cols.Count -lt 4) { continue }

        $role     = $cols[1].Trim()
        $partJson = $cols[3].Trim()
        if ([string]::IsNullOrWhiteSpace($partJson)) { continue }

        try { $part = $partJson | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }

        $ptype = $part.type

        # Rollenwechsel → vorherigen Block flushen
        if ($role -ne $currentRole) {
            if ($null -ne $currentRole -and $msgBuffer.Count -gt 0) {
                $label = if ($currentRole -eq "user") { "### [Du]" } else { "### [Assistant]" }
                [void]$sb.AppendLine($label)
                [void]$sb.AppendLine("")
                foreach ($block in $msgBuffer) { [void]$sb.AppendLine($block) }
                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("---")
                [void]$sb.AppendLine("")
            }
            $currentRole = $role
            $msgBuffer   = [System.Collections.Generic.List[string]]::new()
        }

        switch ($ptype) {
            "text" {
                if (-not [string]::IsNullOrWhiteSpace($part.text)) {
                    $msgBuffer.Add($part.text.Trim())
                }
            }
            "reasoning" {
                if ($INCLUDE_REASONING -and -not [string]::IsNullOrWhiteSpace($part.text)) {
                    $msgBuffer.Add("<details><summary>💭 Reasoning</summary>`n`n$($part.text.Trim())`n`n</details>")
                }
            }
            "tool" {
                $toolName   = $part.tool
                $status     = $part.state.status
                $inputJson  = ($part.state.input | ConvertTo-Json -Compress -Depth 5) 2>$null
                $rawOutput  = if ($part.state.output) { $part.state.output.ToString() } else { "" }
                $output     = Truncate-Text $rawOutput $TOOL_OUTPUT_MAX
                $statusIcon = switch ($status) {
                    "completed" { "OK" }
                    "error"     { "ERR" }
                    default     { "..." }
                }
                $block  = "**[Tool]: ``$toolName``** $statusIcon`n"
                $block += "``````json`n$inputJson`n```````n"
                if (-not [string]::IsNullOrWhiteSpace($output)) {
                    $block += "<details><summary>Output</summary>`n`n``````text`n$output`n```````n`n</details>"
                }
                $msgBuffer.Add($block)
            }
            "subtask" {
                $prompt = if ($part.prompt) { Truncate-Text $part.prompt.ToString() 500 } else { "(kein Prompt)" }
                $block  = "**[Unteragent] (Subtask)**`n"
                $block += "<details><summary>Prompt</summary>`n`n$prompt`n`n</details>"
                $msgBuffer.Add($block)
            }
            "file" {
                $fname = if ($part.filename) { $part.filename } else { "unbekannte Datei" }
                $mime  = if ($part.mime) { $part.mime } else { "" }
                $msgBuffer.Add("**[Datei]:** ``$fname`` *($mime)*")
            }
            # step-start, step-finish, compaction → ignorieren
        }
    }

    # Letzten Block flushen
    if ($null -ne $currentRole -and $msgBuffer.Count -gt 0) {
        $label = if ($currentRole -eq "user") { "### [Du]" } else { "### [Assistant]" }
        [void]$sb.AppendLine($label)
        [void]$sb.AppendLine("")
        foreach ($block in $msgBuffer) { [void]$sb.AppendLine($block) }
        [void]$sb.AppendLine("")
    }

    $content = $sb.ToString()

    if (Test-Path $outPath) {
        $existing = Get-Content $outPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($existing -eq $content) { return $false }
    }

    Set-Content -Path $outPath -Value $content -Encoding UTF8 -NoNewline
    return $true
}

function Run-Watcher {
    $expOutputDir = [System.Environment]::ExpandEnvironmentVariables($OUTPUT_DIR)
    if (-not (Test-Path $expOutputDir)) {
        New-Item -ItemType Directory -Path $expOutputDir -Force | Out-Null
        Write-Log "Output-Ordner erstellt: $expOutputDir"
    }

    if (-not (Get-Command $SQLITE -ErrorAction SilentlyContinue)) {
        Write-Log "FEHLER: sqlite3 nicht gefunden. Installieren: winget install SQLite.SQLite"
        exit 1
    }

    Write-Log "OpenCode Chat Exporter gestartet"
    $expDbPath = [System.Environment]::ExpandEnvironmentVariables($DB_PATH)
    Write-Log "DB:        $expDbPath"
    Write-Log "Output:    $OUTPUT_DIR"
    Write-Log "Poll:      alle $POLL_SEC Sekunden"
    Write-Log "Reasoning: $INCLUDE_REASONING"
    Write-Log "──────────────────────────────────────────"

    $lastDbWrite = [datetime]::MinValue

    while ($true) {
        try {
            if (-not (Test-Path $expDbPath)) {
                Write-Log "DB nicht gefunden, warte..."
                Start-Sleep -Seconds $POLL_SEC
                continue
            }

            $dbWrite = (Get-Item $expDbPath).LastWriteTime

            if ($dbWrite -gt $lastDbWrite) {
                $lastDbWrite = $dbWrite

                $sessionQuery = "SELECT id, title, time_created FROM session WHERE time_archived IS NULL ORDER BY time_updated DESC;"
                $sessions     = & $SQLITE -separator "`t" $expDbPath $sessionQuery 2>$null

                $exported = 0
                foreach ($line in $sessions) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $parts = $line -split "`t"
                    if ($parts.Count -lt 3) { continue }

                    $sid      = $parts[0]
                    $stitle   = $parts[1]
                    $screated = [long]$parts[2]

                    $changed = Export-Session $sid $stitle $screated
                    if ($changed) {
                        $exported++
                        Write-Log "Aktualisiert: $stitle"
                    }
                }
            }
        }
        catch {
            Write-Log "Fehler: $_"
        }

        Start-Sleep -Seconds $POLL_SEC
    }
}

Run-Watcher
