$ErrorActionPreference = 'Stop'

# Start both SPA and API for local development
# Usage: .\scripts\start.ps1

$RootDir = Split-Path -Parent $PSScriptRoot
$SpaDir = Join-Path $RootDir 'sample-app\spa'
$ApiDir = Join-Path $RootDir 'sample-app\api'

# --- Ensure Maven is installed ---
if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
    Write-Host 'Maven not found. Downloading Apache Maven 3.9.15...'
    $mavenVersion = '3.9.15'
    $mavenDir = Join-Path $env:LOCALAPPDATA 'Maven'
    $mavenHome = Join-Path $mavenDir "apache-maven-$mavenVersion"
    $mavenBin = Join-Path $mavenHome 'bin'

    if (-not (Test-Path $mavenBin)) {
        $zipUrl = "https://dlcdn.apache.org/maven/maven-3/$mavenVersion/binaries/apache-maven-$mavenVersion-bin.zip"
        $zipPath = Join-Path $env:TEMP "apache-maven-$mavenVersion-bin.zip"

        Write-Host "Downloading from $zipUrl ..."
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

        Write-Host "Extracting to $mavenDir ..."
        if (-not (Test-Path $mavenDir)) { New-Item -ItemType Directory -Path $mavenDir -Force | Out-Null }
        Expand-Archive -Path $zipPath -DestinationPath $mavenDir -Force
        Remove-Item $zipPath -Force
    }

    # Add to PATH for this session
    $env:Path = "$mavenBin;$env:Path"

    if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
        Write-Error "Maven installation failed. Check $mavenHome"
        exit 1
    }
    Write-Host "Maven $(mvn --version | Select-Object -First 1) installed to $mavenHome"
    Write-Host "To make permanent, add $mavenBin to your system PATH."
}

# --- Install SPA dependencies if needed ---
if (-not (Test-Path (Join-Path $SpaDir 'node_modules'))) {
    Write-Host 'Installing SPA dependencies...'
    Push-Location $SpaDir
    npm install
    Pop-Location
}

# --- Start API (Spring Boot with dev profile) ---
Write-Host 'Starting API on http://localhost:8080 ...'
$currentPath = $env:Path
$apiJob = Start-Job -ScriptBlock {
    param($dir, $path)
    $env:Path = $path
    Set-Location $dir
    mvn spring-boot:run "-Dspring-boot.run.profiles=dev"
} -ArgumentList $ApiDir, $currentPath

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
