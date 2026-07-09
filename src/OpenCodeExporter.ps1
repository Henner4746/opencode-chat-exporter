Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$DEFAULT_DB      = "$env:USERPROFILE\.local\share\opencode\opencode.db"
$DEFAULT_OUTPUT  = "$env:USERPROFILE\Documents\OpenCode_Chats"
$POLL_SEC        = 5
$TOOL_OUTPUT_MAX = 2000
$AUTOSTART_NAME  = "OpenCodeExporter"
$AUTOSTART_KEY   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$EXE_PATH        = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$SETTINGS_PATH   = "$env:APPDATA\OpenCodeExporter\settings.json"

$script:Running          = $false
$script:Timer            = $null
$script:LastDbWrite      = [datetime]::MinValue
$script:IncludeReasoning = $false
$script:DbPath           = $DEFAULT_DB
$script:OutputDir        = $DEFAULT_OUTPUT
$script:ForceClose       = $false

# ── Einstellungen ─────────────────────────────────────────────────────────────
function Load-Settings {
    if (Test-Path $SETTINGS_PATH) {
        try {
            $s = Get-Content $SETTINGS_PATH -Raw | ConvertFrom-Json
            return $s
        } catch {}
    }
    return [PSCustomObject]@{
        DbPath      = $DEFAULT_DB
        OutputDir   = $DEFAULT_OUTPUT
        Reasoning   = $false
        Autostart   = $false
    }
}

function Save-Settings($dbPath, $outputDir, $reasoning, $autostart) {
    $dir = Split-Path $SETTINGS_PATH
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [PSCustomObject]@{
        DbPath    = $dbPath
        OutputDir = $outputDir
        Reasoning = $reasoning
        Autostart = $autostart
    } | ConvertTo-Json | Set-Content $SETTINGS_PATH -Encoding UTF8
}

# ── Autostart ─────────────────────────────────────────────────────────────────
function Get-AutostartEnabled {
    return $null -ne (Get-ItemProperty -Path $AUTOSTART_KEY -Name $AUTOSTART_NAME -ErrorAction SilentlyContinue)
}

function Set-Autostart($enable) {
    if ($enable) {
        Set-ItemProperty -Path $AUTOSTART_KEY -Name $AUTOSTART_NAME -Value "`"$EXE_PATH`" -minimized"
    } else {
        Remove-ItemProperty -Path $AUTOSTART_KEY -Name $AUTOSTART_NAME -ErrorAction SilentlyContinue
    }
}

# ── Tray Icons ────────────────────────────────────────────────────────────────
function New-Icon($color) {
    $bmp = [System.Drawing.Bitmap]::new(16, 16)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillEllipse([System.Drawing.Brushes]::DimGray, 0, 0, 15, 15)
    $brush = [System.Drawing.SolidBrush]::new($color)
    $g.FillEllipse($brush, 3, 3, 9, 9)
    $brush.Dispose(); $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

# ── XAML ──────────────────────────────────────────────────────────────────────
[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OpenCode Chat Exporter"
        Width="520" Height="600"
        ResizeMode="CanMinimize"
        WindowStartupLocation="CenterScreen"
        ShowInTaskbar="False"
        Background="#0f0f0f"
        FontFamily="Consolas">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="12"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="12"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="12"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="12"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="12"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="12"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0">
      <TextBlock Text="OPENCODE CHAT EXPORTER"
                 Foreground="#e0e0e0" FontSize="13" FontWeight="Bold" FontFamily="Consolas"/>
      <Rectangle Height="1" Fill="#2a2a2a" Margin="0,8,0,0"/>
    </StackPanel>

    <StackPanel Grid.Row="2">
      <TextBlock Text="DATENBANK" Foreground="#666" FontSize="10" Margin="0,0,0,3" FontFamily="Consolas"/>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="8"/>
          <ColumnDefinition Width="36"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="TxtDb" Grid.Column="0"
                 Background="#1a1a1a" Foreground="#e0e0e0" BorderBrush="#2a2a2a"
                 BorderThickness="1" Padding="8,6" FontFamily="Consolas" FontSize="11" CaretBrush="#e0e0e0"/>
        <Button x:Name="BtnBrowseDb" Grid.Column="2" Content="..."
                Background="#1e1e1e" Foreground="#888" BorderBrush="#2a2a2a"
                BorderThickness="1" FontFamily="Consolas" Cursor="Hand"/>
      </Grid>
    </StackPanel>

    <StackPanel Grid.Row="4">
      <TextBlock Text="AUSGABE-ORDNER" Foreground="#666" FontSize="10" Margin="0,0,0,3" FontFamily="Consolas"/>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="8"/>
          <ColumnDefinition Width="36"/>
        </Grid.ColumnDefinitions>
        <TextBox x:Name="TxtOutput" Grid.Column="0"
                 Background="#1a1a1a" Foreground="#e0e0e0" BorderBrush="#2a2a2a"
                 BorderThickness="1" Padding="8,6" FontFamily="Consolas" FontSize="11" CaretBrush="#e0e0e0"/>
        <Button x:Name="BtnBrowseOutput" Grid.Column="2" Content="..."
                Background="#1e1e1e" Foreground="#888" BorderBrush="#2a2a2a"
                BorderThickness="1" FontFamily="Consolas" Cursor="Hand"/>
      </Grid>
    </StackPanel>

    <StackPanel Grid.Row="6" Orientation="Horizontal">
      <CheckBox x:Name="ChkReasoning" Content="Reasoning exportieren"
                Foreground="#666" FontFamily="Consolas" FontSize="10" Margin="0,0,20,0"/>
      <CheckBox x:Name="ChkAutostart" Content="Mit Windows starten"
                Foreground="#666" FontFamily="Consolas" FontSize="10"/>
    </StackPanel>

    <Button x:Name="BtnToggle" Grid.Row="8"
            Content="[ START ]" Height="44"
            FontFamily="Consolas" FontSize="12" FontWeight="Bold"
            Background="#1a2a1a" Foreground="#44cc44"
            BorderBrush="#2a4a2a" BorderThickness="1" Cursor="Hand"/>

    <TextBlock x:Name="TxtStatus" Grid.Row="10"
               Text="Bereit." Foreground="#555" FontSize="10"
               FontFamily="Consolas" HorizontalAlignment="Center"/>

    <StackPanel Grid.Row="12">
      <Grid Margin="0,0,0,6">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Text="LOG" Foreground="#666" FontSize="10" FontFamily="Consolas" VerticalAlignment="Center"/>
        <Button x:Name="BtnOpenFolder" Grid.Column="1" Content="Ordner oeffnen"
                Background="Transparent" Foreground="#555" BorderBrush="#2a2a2a"
                BorderThickness="1" Padding="6,3" FontFamily="Consolas" FontSize="9" Cursor="Hand"/>
      </Grid>
      <TextBox x:Name="TxtLog"
               Background="#0a0a0a" Foreground="#44aaff" BorderBrush="#1a1a1a"
               BorderThickness="1" FontFamily="Consolas" FontSize="10"
               Padding="8" IsReadOnly="True" Height="140"
               TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
    </StackPanel>
  </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($XAML)
$Window = [Windows.Markup.XamlReader]::Load($reader)

$TxtDb         = $Window.FindName("TxtDb")
$TxtOutput     = $Window.FindName("TxtOutput")
$BtnBrowseDb   = $Window.FindName("BtnBrowseDb")
$BtnBrowseOut  = $Window.FindName("BtnBrowseOutput")
$ChkReasoning  = $Window.FindName("ChkReasoning")
$ChkAutostart  = $Window.FindName("ChkAutostart")
$BtnToggle     = $Window.FindName("BtnToggle")
$TxtLog        = $Window.FindName("TxtLog")
$TxtStatus     = $Window.FindName("TxtStatus")
$BtnOpenFolder = $Window.FindName("BtnOpenFolder")

# Einstellungen laden
$cfg = Load-Settings
$TxtDb.Text             = $cfg.DbPath
$TxtOutput.Text         = $cfg.OutputDir
$ChkReasoning.IsChecked = [bool]$cfg.Reasoning
$ChkAutostart.IsChecked = Get-AutostartEnabled

# ── Tray ──────────────────────────────────────────────────────────────────────
$tray            = [System.Windows.Forms.NotifyIcon]::new()
$tray.Icon       = New-Icon ([System.Drawing.Color]::Crimson)
$tray.Text       = "OpenCode Exporter - Gestoppt"
$tray.Visible    = $true

$ctxMenu         = [System.Windows.Forms.ContextMenuStrip]::new()
$menuShow        = $ctxMenu.Items.Add("Fenster anzeigen")
$menuStartStop   = $ctxMenu.Items.Add("Start")
$ctxMenu.Items.Add("-") | Out-Null
$menuExit        = $ctxMenu.Items.Add("Beenden")
$tray.ContextMenuStrip = $ctxMenu

# ── Helpers ───────────────────────────────────────────────────────────────────
function Add-Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $Window.Dispatcher.Invoke([Action]{
        $TxtLog.AppendText("[$ts] $msg`n")
        $TxtLog.ScrollToEnd()
    })
}

function Set-Status($msg) {
    $Window.Dispatcher.Invoke([Action]{ $TxtStatus.Text = $msg })
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
    return $text.Substring(0, $max) + "`n... [gekuerzt]"
}

function Export-Session($sessionId, $sessionTitle, $sessionCreated, $dbPath, $outputDir, $inclReasoning) {
    $dateObj  = [DateTimeOffset]::FromUnixTimeMilliseconds($sessionCreated).LocalDateTime
    $safeName = Sanitize-Filename $sessionTitle
    $filename = "$($dateObj.ToString('yyyy-MM-dd'))_$($dateObj.ToString('HH-mm'))_${safeName}.md"
    $outPath  = Join-Path $outputDir $filename

    $query = "SELECT m.time_created, json_extract(m.data, '$.role'), p.time_created, p.data FROM message m LEFT JOIN part p ON p.message_id = m.id WHERE m.session_id = '$sessionId' ORDER BY m.time_created ASC, p.time_created ASC;"
    $rows  = & sqlite3 -separator "|||" $dbPath $query 2>$null
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
        try { $part = $partJson | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $ptype = $part.type

        if ($role -ne $currentRole) {
            if ($null -ne $currentRole -and $msgBuffer.Count -gt 0) {
                $label = if ($currentRole -eq "user") { "### [Du]" } else { "### [Assistant]" }
                [void]$sb.AppendLine($label); [void]$sb.AppendLine("")
                foreach ($b in $msgBuffer) { [void]$sb.AppendLine($b) }
                [void]$sb.AppendLine(""); [void]$sb.AppendLine("---"); [void]$sb.AppendLine("")
            }
            $currentRole = $role
            $msgBuffer   = [System.Collections.Generic.List[string]]::new()
        }

        switch ($ptype) {
            "text" {
                if (-not [string]::IsNullOrWhiteSpace($part.text)) { $msgBuffer.Add($part.text.Trim()) }
            }
            "reasoning" {
                if ($inclReasoning -and -not [string]::IsNullOrWhiteSpace($part.text)) {
                    $msgBuffer.Add("<details><summary>[Reasoning]</summary>`n`n$($part.text.Trim())`n`n</details>")
                }
            }
            "tool" {
                $inputJson  = ($part.state.input | ConvertTo-Json -Compress -Depth 5) 2>$null
                $output     = Truncate-Text ($part.state.output.ToString()) $TOOL_OUTPUT_MAX
                $statusIcon = switch ($part.state.status) { "completed" {"OK"} "error" {"ERR"} default {"..."} }
                $block  = "**[Tool: $($part.tool)] [$statusIcon]**`n``````json`n$inputJson`n```````n"
                if (-not [string]::IsNullOrWhiteSpace($output)) {
                    $block += "<details><summary>Output</summary>`n`n``````text`n$output`n```````n`n</details>"
                }
                $msgBuffer.Add($block)
            }
            "subtask" {
                $prompt = if ($part.prompt) { Truncate-Text $part.prompt.ToString() 500 } else { "(kein Prompt)" }
                $msgBuffer.Add("**[Unteragent]**`n<details><summary>Prompt</summary>`n`n$prompt`n`n</details>")
            }
            "file" {
                $fname = if ($part.filename) { $part.filename } else { "unbekannte Datei" }
                $mime  = if ($part.mime) { $part.mime } else { "" }
                $msgBuffer.Add("**[Datei: $fname]** ($mime)")
            }
        }
    }

    if ($null -ne $currentRole -and $msgBuffer.Count -gt 0) {
        $label = if ($currentRole -eq "user") { "### [Du]" } else { "### [Assistant]" }
        [void]$sb.AppendLine($label); [void]$sb.AppendLine("")
        foreach ($b in $msgBuffer) { [void]$sb.AppendLine($b) }
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

# ── Start / Stop ──────────────────────────────────────────────────────────────
function Start-Watcher {
    $dbPath    = $TxtDb.Text.Trim()
    $outputDir = $TxtOutput.Text.Trim()

    if (-not (Test-Path $dbPath)) { Add-Log "FEHLER: DB nicht gefunden: $dbPath"; return }
    if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) { Add-Log "FEHLER: sqlite3 nicht gefunden"; return }
    if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

    $script:Running          = $true
    $script:DbPath           = $dbPath
    $script:OutputDir        = $outputDir
    $script:IncludeReasoning = [bool]$ChkReasoning.IsChecked
    $script:LastDbWrite      = [datetime]::MinValue

    Save-Settings $dbPath $outputDir $script:IncludeReasoning (Get-AutostartEnabled)

    $BtnToggle.Content     = "[ STOP ]"
    $BtnToggle.Background  = [Windows.Media.SolidColorBrush]([Windows.Media.Color]::FromRgb(0x2a,0x0a,0x0a))
    $BtnToggle.Foreground  = [Windows.Media.SolidColorBrush]([Windows.Media.Color]::FromRgb(0xcc,0x44,0x44))
    $BtnToggle.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.Color]::FromRgb(0x4a,0x1a,0x1a))
    $TxtDb.IsEnabled = $false; $TxtOutput.IsEnabled = $false
    $BtnBrowseDb.IsEnabled = $false; $BtnBrowseOut.IsEnabled = $false
    $ChkReasoning.IsEnabled = $false

    $tray.Icon = New-Icon ([System.Drawing.Color]::LimeGreen)
    $tray.Text = "OpenCode Exporter - Laeuft"
    $menuStartStop.Text = "Stop"
    Set-Status "Laeuft - alle $POLL_SEC Sek."
    Add-Log "Watcher gestartet."

    $script:Timer          = [System.Windows.Threading.DispatcherTimer]::new()
    $script:Timer.Interval = [TimeSpan]::FromSeconds($POLL_SEC)
    $script:Timer.Add_Tick({
        try {
            if (-not (Test-Path $script:DbPath)) { return }
            $dbWrite = (Get-Item $script:DbPath).LastWriteTime
            if ($dbWrite -le $script:LastDbWrite) { return }
            $script:LastDbWrite = $dbWrite
            $sessions = & sqlite3 -separator "`t" $script:DbPath "SELECT id, title, time_created FROM session WHERE time_archived IS NULL ORDER BY time_updated DESC;" 2>$null
            $count = 0
            foreach ($line in $sessions) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $p = $line -split "`t"
                if ($p.Count -lt 3) { continue }
                $changed = Export-Session $p[0] $p[1] ([long]$p[2]) $script:DbPath $script:OutputDir $script:IncludeReasoning
                if ($changed) { Add-Log "Gespeichert: $($p[1])"; $count++ }
            }
            if ($count -gt 0) {
                $tray.ShowBalloonTip(2000, "OpenCode Exporter", "$count Chat(s) aktualisiert", [System.Windows.Forms.ToolTipIcon]::None)
            }
            Set-Status "Zuletzt: $(Get-Date -Format 'HH:mm:ss')"
        } catch { Add-Log "Fehler: $_" }
    })
    $script:Timer.Start()
}

function Stop-Watcher {
    if ($script:Timer) { $script:Timer.Stop(); $script:Timer = $null }
    $script:Running = $false

    $BtnToggle.Content     = "[ START ]"
    $BtnToggle.Background  = [Windows.Media.SolidColorBrush]([Windows.Media.Color]::FromRgb(0x1a,0x2a,0x1a))
    $BtnToggle.Foreground  = [Windows.Media.SolidColorBrush]([Windows.Media.Color]::FromRgb(0x44,0xcc,0x44))
    $BtnToggle.BorderBrush = [Windows.Media.SolidColorBrush]([Windows.Media.Color]::FromRgb(0x2a,0x4a,0x2a))
    $TxtDb.IsEnabled = $true; $TxtOutput.IsEnabled = $true
    $BtnBrowseDb.IsEnabled = $true; $BtnBrowseOut.IsEnabled = $true
    $ChkReasoning.IsEnabled = $true

    $tray.Icon = New-Icon ([System.Drawing.Color]::Crimson)
    $tray.Text = "OpenCode Exporter - Gestoppt"
    $menuStartStop.Text = "Start"
    Set-Status "Gestoppt."
    Add-Log "Gestoppt."
}

# ── Events ────────────────────────────────────────────────────────────────────
$BtnToggle.Add_Click({ if ($script:Running) { Stop-Watcher } else { Start-Watcher } })

$ChkAutostart.Add_Click({
    Set-Autostart $ChkAutostart.IsChecked
    Save-Settings $TxtDb.Text $TxtOutput.Text ([bool]$ChkReasoning.IsChecked) ([bool]$ChkAutostart.IsChecked)
    Add-Log "Autostart: $(if ($ChkAutostart.IsChecked) { 'aktiviert' } else { 'deaktiviert' })"
})

$ChkReasoning.Add_Click({
    Save-Settings $TxtDb.Text $TxtOutput.Text ([bool]$ChkReasoning.IsChecked) (Get-AutostartEnabled)
})

$BtnBrowseDb.Add_Click({
    $dlg = [Microsoft.Win32.OpenFileDialog]::new()
    $dlg.Filter = "SQLite Datenbank|*.db|Alle Dateien|*.*"
    $dlg.FileName = $TxtDb.Text
    if ($dlg.ShowDialog()) { $TxtDb.Text = $dlg.FileName }
})

$BtnBrowseOut.Add_Click({
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.SelectedPath = $TxtOutput.Text
    if ($dlg.ShowDialog() -eq "OK") { $TxtOutput.Text = $dlg.SelectedPath }
})

$BtnOpenFolder.Add_Click({
    $path = $TxtOutput.Text.Trim()
    if (Test-Path $path) { Start-Process explorer.exe $path }
    else { Add-Log "Ordner existiert noch nicht." }
})

$Window.Add_StateChanged({
    if ($Window.WindowState -eq [Windows.WindowState]::Minimized) { $Window.Hide() }
})

$Window.Add_Closing({
    param($s, $e)
    if (-not $script:ForceClose) {
        $e.Cancel = $true
        $Window.Hide()
    }
})

$tray.Add_DoubleClick({
    $Window.Show()
    $Window.WindowState = [Windows.WindowState]::Normal
    $Window.Activate()
})

$menuShow.Add_Click({
    $Window.Show()
    $Window.WindowState = [Windows.WindowState]::Normal
    $Window.Activate()
})

$menuStartStop.Add_Click({ if ($script:Running) { Stop-Watcher } else { Start-Watcher } })

$menuExit.Add_Click({
    if ($script:Running) { Stop-Watcher }
    $tray.Visible = $false
    $tray.Dispose()
    $script:ForceClose = $true
    $Window.Close()
})

# ── Start ─────────────────────────────────────────────────────────────────────
Add-Log "Bereit. DB: $($TxtDb.Text)"

$cmdArgs = [System.Environment]::GetCommandLineArgs()
if ($args -contains "-minimized" -or $cmdArgs -contains "-minimized") {
    $Window.Show()
    $Window.WindowState = [Windows.WindowState]::Minimized
    $Window.Hide()
    Start-Watcher
} else {
    $Window.Show()
    [System.Windows.Threading.Dispatcher]::Run()
}
