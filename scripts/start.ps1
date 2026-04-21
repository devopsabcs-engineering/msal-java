$ErrorActionPreference = 'Stop'

# Start both SPA and API for local development
# Usage: .\scripts\start.ps1

$RootDir = Split-Path -Parent $PSScriptRoot
$SpaDir = Join-Path $RootDir 'sample-app\spa'
$ApiDir = Join-Path $RootDir 'sample-app\api'

# --- Install SPA dependencies if needed ---
if (-not (Test-Path (Join-Path $SpaDir 'node_modules'))) {
    Write-Host 'Installing SPA dependencies...'
    Push-Location $SpaDir
    npm install
    Pop-Location
}

# --- Start API (Spring Boot with dev profile) ---
Write-Host 'Starting API on http://localhost:8080 ...'
$apiJob = Start-Job -ScriptBlock {
    param($dir)
    Set-Location $dir
    mvn spring-boot:run "-Dspring-boot.run.profiles=dev"
} -ArgumentList $ApiDir

# --- Start SPA (Angular dev server with proxy) ---
Write-Host 'Starting SPA on http://localhost:4200 ...'
$spaJob = Start-Job -ScriptBlock {
    param($dir)
    Set-Location $dir
    npx ng serve --proxy-config proxy.conf.json --open
} -ArgumentList $SpaDir

Write-Host ''
Write-Host '  SPA: http://localhost:4200'
Write-Host '  API: http://localhost:8080'
Write-Host ''
Write-Host 'Press Ctrl+C to stop both.'

try {
    while ($true) {
        # Stream output from both jobs
        Receive-Job -Job $apiJob -ErrorAction SilentlyContinue
        Receive-Job -Job $spaJob -ErrorAction SilentlyContinue

        if ($apiJob.State -eq 'Failed') {
            Write-Host 'API job failed:' -ForegroundColor Red
            Receive-Job -Job $apiJob
            break
        }
        if ($spaJob.State -eq 'Failed') {
            Write-Host 'SPA job failed:' -ForegroundColor Red
            Receive-Job -Job $spaJob
            break
        }

        Start-Sleep -Milliseconds 500
    }
}
finally {
    Write-Host 'Shutting down...'
    Stop-Job -Job $apiJob -ErrorAction SilentlyContinue
    Stop-Job -Job $spaJob -ErrorAction SilentlyContinue
    Remove-Job -Job $apiJob -Force -ErrorAction SilentlyContinue
    Remove-Job -Job $spaJob -Force -ErrorAction SilentlyContinue
}
