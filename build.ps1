# build.ps1 — kompiliert OpenCodeExporter.ps1 zu einer .exe
# Voraussetzung: Install-Module ps2exe -Scope CurrentUser -Force

$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "ps2exe nicht installiert. Installiere..." -ForegroundColor Yellow
    Install-Module ps2exe -Scope CurrentUser -Force
}

$srcPath = Join-Path $PSScriptRoot "src\OpenCodeExporter.ps1"
$distDir = Join-Path $PSScriptRoot "dist"
$outPath = Join-Path $distDir "OpenCodeExporter.exe"

if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir | Out-Null
}

Write-Host "Kompiliere $srcPath -> $outPath ..." -ForegroundColor Cyan

ps2exe `
    -inputFile $srcPath `
    -outputFile $outPath `
    -noConsole `
    -title "OpenCode Chat Exporter" `
    -version "1.0.0" `
    -company "Community" `
    -product "OpenCode Chat Exporter"

Write-Host "Fertig: $outPath" -ForegroundColor Green
