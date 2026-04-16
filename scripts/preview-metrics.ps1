param(
    [string]$User = "chronooo",
    [string]$Timezone = "Asia/Tokyo",
    [string]$EnvFile = ".env.metrics",
    [string]$OutDir = "metrics-preview",
    [string]$Image = "ghcr.io/lowlighter/metrics:v3.34",
    [bool]$SyncToRoot = $true,
    [switch]$Sequential,
    [switch]$PullLatest
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

function Invoke-MetricsRender {
    param(
        [string]$Label,
        [string[]]$RenderArgs,
        [string]$MetricsImage
    )

    Write-Host "Rendering $Label..."
    docker run --rm @RenderArgs $MetricsImage | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Render failed for $Label (docker exit code: $LASTEXITCODE)"
    }
}

function Invoke-MetricsRenderParallel {
    param(
        [object[]]$RenderSet,
        [string]$MetricsImage
    )

    Write-Host "Rendering in parallel ($($RenderSet.Count) jobs)..."
    $jobs = @()
    foreach ($render in $RenderSet) {
        $jobs += Start-Job -Name $render.Label -ScriptBlock {
            param($Label, $RenderArgs, $MetricsImage)
            $tmp = [System.IO.Path]::GetTempFileName()
            & docker run --rm @RenderArgs $MetricsImage *> $tmp
            $exitCode = $LASTEXITCODE
            $output = ""
            if ($exitCode -ne 0) {
                $output = Get-Content -LiteralPath $tmp -Raw
            }
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            [pscustomobject]@{
                Label = $Label
                ExitCode = $exitCode
                Output = $output
            }
        } -ArgumentList $render.Label, $render.RenderArgs, $MetricsImage
    }

    Wait-Job -Job $jobs | Out-Null

    $results = @{}
    foreach ($job in $jobs) {
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force
        if ($null -eq $result) {
            throw "Parallel render job failed unexpectedly: $($job.Name)"
        }
        $results[$result.Label] = $result
    }

    foreach ($render in $RenderSet) {
        $result = $results[$render.Label]
        Write-Host "Rendering $($result.Label)... done"
        if ($result.ExitCode -ne 0) {
            if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
                Write-Host $result.Output.TrimEnd()
            }
            throw "Render failed for $($result.Label) (docker exit code: $($result.ExitCode))"
        }
    }
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

if ($PullLatest) {
    Write-Host "Pulling metrics image: $Image"
    docker pull $Image | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to pull $Image"
    }
}
else {
    docker image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Image not found locally. Pulling: $Image"
        docker pull $Image | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to pull $Image"
        }
    }
    else {
        Write-Host "Using local image: $Image"
    }
}

$languageArgs = @(
    "-e", "INPUT_TOKEN=$token",
    "-e", "INPUT_USER=$User",
    "-e", "INPUT_FILENAME=github-metrics-languages.svg",
    "-e", "INPUT_BASE=",
    "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
    "-e", "INPUT_PLUGIN_LANGUAGES=yes",
    "-v", "${outPath}:/renders"
)

$renderSet = @(
    [pscustomobject]@{
        Label = "github-metrics.svg"
        RenderArgs = @(
            "-e", "INPUT_TOKEN=$token",
            "-e", "INPUT_USER=$User",
            "-e", "INPUT_FILENAME=github-metrics.svg",
            "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
            "-e", "INPUT_REPOSITORIES_AFFILIATIONS=owner, collaborator, organization_member",
            "-e", "INPUT_PLUGIN_REPOSITORIES=yes",
            "-e", "INPUT_PLUGIN_REPOSITORIES_PINNED=6",
            "-e", "INPUT_PLUGIN_REPOSITORIES_AFFILIATIONS=owner, collaborator, organization_member",
            "-v", "${outPath}:/renders"
        )
    },
    [pscustomobject]@{
        Label = "github-metrics-languages.svg"
        RenderArgs = $languageArgs
    },
    [pscustomobject]@{
        Label = "github-metrics-isocalendar.svg"
        RenderArgs = @(
            "-e", "INPUT_TOKEN=$token",
            "-e", "INPUT_USER=$User",
            "-e", "INPUT_FILENAME=github-metrics-isocalendar.svg",
            "-e", "INPUT_BASE=",
            "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
            "-e", "INPUT_PLUGIN_ISOCALENDAR=yes",
            "-e", "INPUT_PLUGIN_ISOCALENDAR_DURATION=full-year",
            "-v", "${outPath}:/renders"
        )
    },
    [pscustomobject]@{
        Label = "github-metrics-stars.svg"
        RenderArgs = @(
            "-e", "INPUT_TOKEN=$token",
            "-e", "INPUT_USER=$User",
            "-e", "INPUT_FILENAME=github-metrics-stars.svg",
            "-e", "INPUT_BASE=",
            "-e", "INPUT_CONFIG_TIMEZONE=$Timezone",
            "-e", "INPUT_PLUGIN_STARS=yes",
            "-e", "INPUT_PLUGIN_STARS_LIMIT=6",
            "-v", "${outPath}:/renders"
        )
    }
)

if ($Sequential) {
    foreach ($render in $renderSet) {
        Invoke-MetricsRender -Label $render.Label -RenderArgs $render.RenderArgs -MetricsImage $Image
    }
}
else {
    Invoke-MetricsRenderParallel -RenderSet $renderSet -MetricsImage $Image
}

if ($SyncToRoot) {
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics.svg") -Destination ".\\github-metrics.svg" -Force
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics-languages.svg") -Destination ".\\github-metrics-languages.svg" -Force
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics-isocalendar.svg") -Destination ".\\github-metrics-isocalendar.svg" -Force
    Copy-Item -LiteralPath (Join-Path $outPath "github-metrics-stars.svg") -Destination ".\\github-metrics-stars.svg" -Force
    Write-Host "Synced rendered SVGs to repository root for README preview."
}

Write-Host ""
Write-Host "Done. Preview SVGs are in: $outPath"
