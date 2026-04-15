param(
    [string]$User = "chronooo",
    [string]$Timezone = "Asia/Tokyo",
    [string]$EnvFile = ".env.metrics",
    [string]$OutDir = "metrics-preview",
    [string]$Image = "ghcr.io/lowlighter/metrics:v3.34",
    [bool]$SyncToRoot = $true
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

function Get-OptionalEnvValue {
    param(
        [string]$Path,
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if (-not $line) {
        return ""
    }

    return ($line -split "=", 2)[1].Trim()
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is required but was not found in PATH."
}

function Invoke-MetricsRender {
    param(
        [string[]]$RenderArgs,
        [string]$Label
    )

    Write-Host "Rendering $Label..."
    docker run --rm @RenderArgs $Image | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Render failed for $Label (docker exit code: $LASTEXITCODE)"
    }
}

$token = Get-EnvValue -Path $EnvFile -Key "METRICS_TOKEN"
if ([string]::IsNullOrWhiteSpace($token) -or $token -match "PASTE_YOUR_GITHUB_CLASSIC_PAT_HERE") {
    throw "Set a real METRICS_TOKEN value in $EnvFile before running."
}
 
$commitsAuthoring = ".user.login, .user.email, 99775368+chronooo@users.noreply.github.com"
$extraCommitsAuthoring = Get-OptionalEnvValue -Path $EnvFile -Key "METRICS_COMMITS_AUTHORING"
if (-not [string]::IsNullOrWhiteSpace($extraCommitsAuthoring)) {
    $commitsAuthoring = "$commitsAuthoring, $extraCommitsAuthoring"
}
$indepthCustom = Get-OptionalEnvValue -Path $EnvFile -Key "METRICS_LANG_INDEPTH_CUSTOM"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outPath = (Resolve-Path -LiteralPath $OutDir).Path

Write-Host "Pulling metrics image: $Image"
docker pull $Image | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Unable to pull $Image"
}

Invoke-MetricsRender -Label "github-metrics.svg" -RenderArgs @(
    "-e", "INPUT_TOKEN=$token",
    "-e", "INPUT_USER=$User",
    "-e", "INPUT_FILENAME=github-metrics.svg",
    "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
    "-e", "INPUT_PLUGIN_REPOSITORIES=yes",
    "-e", "INPUT_PLUGIN_REPOSITORIES_PINNED=6",
    "-v", "${outPath}:/renders"
)

Invoke-MetricsRender -Label "github-metrics-languages.svg" -RenderArgs @(
    "-e", "INPUT_TOKEN=$token",
    "-e", "INPUT_USER=$User",
    "-e", "INPUT_FILENAME=github-metrics-languages.svg",
    "-e", "INPUT_BASE=",
    "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
    "-e", "INPUT_REPOSITORIES_AFFILIATIONS=owner, collaborator, organization_member",
    "-e", "INPUT_COMMITS_AUTHORING=$commitsAuthoring",
    "-e", "INPUT_PLUGIN_LANGUAGES=yes",
    "-e", "INPUT_PLUGIN_LANGUAGES_LIMIT=8",
    "-e", "INPUT_PLUGIN_LANGUAGES_DETAILS=bytes-size, percentage",
    "-e", "INPUT_PLUGIN_LANGUAGES_SECTIONS=most-used",
    "-e", "INPUT_PLUGIN_LANGUAGES_INDEPTH=yes",
    "-e", "INPUT_PLUGIN_LANGUAGES_INDEPTH_CUSTOM=$indepthCustom",
    "-e", "INPUT_PLUGIN_LANGUAGES_ANALYSIS_TIMEOUT=120",
    "-e", "INPUT_PLUGIN_LANGUAGES_ANALYSIS_TIMEOUT_REPOSITORIES=20",
    "-e", "INPUT_PLUGIN_LANGUAGES_IGNORED=html, css, tex, less, dockerfile, makefile, qmake, lex, cmake, shell, gnuplot",
    "-v", "${outPath}:/renders"
)

Invoke-MetricsRender -Label "github-metrics-isocalendar.svg" -RenderArgs @(
    "-e", "INPUT_TOKEN=$token",
    "-e", "INPUT_USER=$User",
    "-e", "INPUT_FILENAME=github-metrics-isocalendar.svg",
    "-e", "INPUT_BASE=",
    "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
    "-e", "INPUT_PLUGIN_ISOCALENDAR=yes",
    "-e", "INPUT_PLUGIN_ISOCALENDAR_DURATION=full-year",
    "-v", "${outPath}:/renders"
)

Invoke-MetricsRender -Label "github-metrics-stars.svg" -RenderArgs @(
    "-e", "INPUT_TOKEN=$token",
    "-e", "INPUT_USER=$User",
    "-e", "INPUT_FILENAME=github-metrics-stars.svg",
    "-e", "INPUT_BASE=",
    "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
    "-e", "INPUT_PLUGIN_STARS=yes",
    "-e", "INPUT_PLUGIN_STARS_LIMIT=4",
    "-v", "${outPath}:/renders"
)

if ($SyncToRoot) {
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics.svg") -Destination ".\\github-metrics.svg" -Force
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics-languages.svg") -Destination ".\\github-metrics-languages.svg" -Force
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics-isocalendar.svg") -Destination ".\\github-metrics-isocalendar.svg" -Force
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics-stars.svg") -Destination ".\\github-metrics-stars.svg" -Force
    Write-Host "Synced rendered SVGs to repository root for README preview."
}

Write-Host ""
Write-Host "Done. Preview SVGs are in: $outPath"
