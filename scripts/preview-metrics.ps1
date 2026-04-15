param(
    [string]$User = "chronooo",
    [string]$Timezone = "Asia/Tokyo",
    [string]$EnvFile = ".env.metrics",
    [string]$OutDir = "metrics-preview"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-EnvValue {
    param(
        [string]$Path,
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Env file not found: $Path"
    }

    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if (-not $line) {
        throw "Missing $Key in $Path"
    }

    return ($line -split "=", 2)[1].Trim()
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is required but was not found in PATH."
}

$token = Get-EnvValue -Path $EnvFile -Key "METRICS_TOKEN"
if ([string]::IsNullOrWhiteSpace($token) -or $token -match "PASTE_YOUR_GITHUB_CLASSIC_PAT_HERE") {
    throw "Set a real METRICS_TOKEN value in $EnvFile before running."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outPath = (Resolve-Path -LiteralPath $OutDir).Path

Write-Host "Rendering github-metrics.svg..."
docker run --rm `
    -e INPUT_TOKEN=$token `
    -e INPUT_USER=$User `
    -e INPUT_FILENAME=github-metrics.svg `
    -e INPUT_CONFIG_TIMEZONE=$Timezone `
    -e INPUT_PLUGIN_REPOSITORIES=yes `
    -e INPUT_PLUGIN_REPOSITORIES_PINNED=6 `
    -v "${outPath}:/renders" `
    lowlighter/metrics:v3.34 | Out-Host

Write-Host "Rendering github-metrics-languages.svg..."
docker run --rm `
    -e INPUT_TOKEN=$token `
    -e INPUT_USER=$User `
    -e INPUT_FILENAME=github-metrics-languages.svg `
    -e INPUT_BASE= `
    -e INPUT_CONFIG_TIMEZONE=$Timezone `
    -e INPUT_PLUGIN_LANGUAGES=yes `
    -e INPUT_PLUGIN_LANGUAGES_LIMIT=8 `
    -e INPUT_PLUGIN_LANGUAGES_DETAILS="bytes-size, percentage" `
    -e INPUT_PLUGIN_LANGUAGES_IGNORED="html, css, tex, less, dockerfile, makefile, qmake, lex, cmake, shell, gnuplot" `
    -v "${outPath}:/renders" `
    lowlighter/metrics:v3.34 | Out-Host

Write-Host "Rendering github-metrics-isocalendar.svg..."
docker run --rm `
    -e INPUT_TOKEN=$token `
    -e INPUT_USER=$User `
    -e INPUT_FILENAME=github-metrics-isocalendar.svg `
    -e INPUT_BASE= `
    -e INPUT_CONFIG_TIMEZONE=$Timezone `
    -e INPUT_PLUGIN_ISOCALENDAR=yes `
    -e INPUT_PLUGIN_ISOCALENDAR_DURATION=full-year `
    -v "${outPath}:/renders" `
    lowlighter/metrics:v3.34 | Out-Host

Write-Host ""
Write-Host "Done. Preview SVGs are in: $outPath"
