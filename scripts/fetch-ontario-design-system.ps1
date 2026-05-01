#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Downloads the Ontario Design System distribution package into the SPA's
    src/assets/vendor folder. Idempotent: skips when the version already exists.

.DESCRIPTION
    The Ontario Design System (designsystem.ontario.ca) is a publicly distributed
    set of CSS/SCSS, fonts, icons, and HTML samples maintained by the Government
    of Ontario. The SPA imports `ds-theme.min.css` at build time so the user
    interface follows ontario.ca styling.

    The vendor folder is git-ignored. This script fetches the assets fresh on
    every developer machine / build server and is invoked automatically by
    start.ps1 and deploy.ps1.

.PARAMETER Version
    Distribution package version to download. Defaults to 2.6.0.

.PARAMETER VendorDir
    Target directory (relative to repo root). Defaults to
    sample-app/spa/src/assets/vendor.

.PARAMETER Force
    Re-download even if the target version already exists.
#>
[CmdletBinding()]
param(
    [string]$Version    = '2.6.0',
    [string]$VendorDir  = 'sample-app/spa/public/vendor',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$RepoRoot     = Resolve-Path (Join-Path $PSScriptRoot '..')
$AbsVendorDir = Join-Path $RepoRoot $VendorDir
$TargetDir    = Join-Path $AbsVendorDir 'ontario-design-system'
$VersionFile  = Join-Path $TargetDir '.installed-version'

if (-not $Force -and (Test-Path $VersionFile) -and ((Get-Content -LiteralPath $VersionFile -Raw).Trim() -eq $Version)) {
    Write-Host "Ontario Design System $Version already present at $TargetDir"
    exit 0
}

Write-Host "Downloading Ontario Design System $Version..."

if (-not (Test-Path $AbsVendorDir)) {
    New-Item -ItemType Directory -Path $AbsVendorDir -Force | Out-Null
}

$zipUrl  = "https://designsystem.ontario.ca/dist/ontario-design-system-dist-$Version.zip"
# Use [System.IO.Path]::GetTempPath() so this works on Linux GitHub runners
# (where $env:TEMP is undefined) as well as Windows/macOS.
$zipPath = Join-Path ([System.IO.Path]::GetTempPath()) "ontario-design-system-$Version.zip"

if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

if (Test-Path $TargetDir) { Remove-Item $TargetDir -Recurse -Force }
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

Expand-Archive -LiteralPath $zipPath -DestinationPath $TargetDir -Force
Remove-Item $zipPath -Force

# Trim noise that we never reference at build time to keep the SPA bundle small.
foreach ($prune in @(
    'html-samples',
    'index.html',
    'package.json',
    'styles/components',
    'styles/sass',
    'fonts/ds-fonts.zip',
    'fonts/ds-fonts-desktop.zip'
)) {
    $p = Join-Path $TargetDir $prune
    if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
}
Get-ChildItem -Path $TargetDir -Filter 'version-release-notes-*.*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

Set-Content -LiteralPath $VersionFile -Value $Version -Encoding ascii

Write-Host "Installed Ontario Design System $Version to $TargetDir"
