param(
    [string]$Vivado = "vivado",
    [int]$Jobs = 8,
    [switch]$SkipSynthesis,
    [switch]$SummaryOnly
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TclScript = Join-Path $Root "build_performance_explore_bit.tcl"
$ProjectFile = Join-Path $Root "digital_twin.xpr"
$StableBit = Join-Path $Root "top_performance_explore.bit"
$TimingRpt = Join-Path $Root "timing_performance_explore_bit.rpt"
$PathsRpt = Join-Path $Root "timing_performance_explore_bit_paths.rpt"
$TclSummary = Join-Path $Root "timing_performance_explore_bit_summary.txt"
$PsSummary = Join-Path $Root "build_performance_explore_bit_ps_summary.txt"

function Require-File {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Cannot find $Name`: $Path"
    }
}

function Get-KeyValueFile {
    param([string]$Path)
    $map = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match '^([^=]+)=(.*)$') {
                $map[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }
    return $map
}

function Get-DesignTimingSummary {
    param([string]$Path)
    $result = [ordered]@{
        WNS = ""
        TNS = ""
        FailingEndpoints = ""
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return $result
    }

    $lines = Get-Content -LiteralPath $Path
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*WNS\(ns\)\s+TNS\(ns\)\s+TNS Failing Endpoints') {
            for ($j = $i + 1; $j -lt [Math]::Min($i + 12, $lines.Count); $j++) {
                if ($lines[$j] -match '^\s*([+-]?(?:\d+(?:\.\d+)?|NA))\s+([+-]?(?:\d+(?:\.\d+)?|NA))\s+(\d+|NA)\s+') {
                    $result.WNS = $Matches[1]
                    $result.TNS = $Matches[2]
                    $result.FailingEndpoints = $Matches[3]
                    return $result
                }
            }
        }
    }
    return $result
}

function Get-LatestNamedBit {
    param([string]$Root)
    Get-ChildItem -LiteralPath $Root -Filter "top_performance_explore_*.bit" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

Require-File -Path $TclScript -Name "TCL build script"
Require-File -Path $ProjectFile -Name "Vivado project"

Push-Location $Root
try {
    if (-not $SummaryOnly) {
        $vivadoCommand = Get-Command $Vivado -ErrorAction SilentlyContinue
        if (-not $vivadoCommand) {
            throw "Cannot find Vivado command '$Vivado'. Run this from a Vivado-enabled shell, or pass -Vivado with the full path to vivado.bat."
        }
        $vivadoExe = if ($vivadoCommand.Source) { $vivadoCommand.Source } else { $vivadoCommand.Definition }

        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $log = Join-Path $Root "build_performance_explore_bit_ps_$stamp.log"
        $jou = Join-Path $Root "build_performance_explore_bit_ps_$stamp.jou"

        $oldJobs = $env:VIVADO_JOBS
        $oldResetSynth = $env:VIVADO_RESET_SYNTH
        $env:VIVADO_JOBS = [string]$Jobs
        $env:VIVADO_RESET_SYNTH = if ($SkipSynthesis) { "0" } else { "1" }
        Write-Host "Running Vivado Performance_Explore build..."
        Write-Host "Vivado       : $vivadoExe"
        Write-Host "Jobs         : $Jobs"
        Write-Host "Reset synth  : $(-not $SkipSynthesis)"
        Write-Host "TCL          : $TclScript"
        Write-Host "Log          : $log"

        try {
            & $vivadoExe -mode batch -source $TclScript -journal $jou -log $log
            $exitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $oldJobs) {
                Remove-Item Env:\VIVADO_JOBS -ErrorAction SilentlyContinue
            } else {
                $env:VIVADO_JOBS = $oldJobs
            }
            if ($null -eq $oldResetSynth) {
                Remove-Item Env:\VIVADO_RESET_SYNTH -ErrorAction SilentlyContinue
            } else {
                $env:VIVADO_RESET_SYNTH = $oldResetSynth
            }
        }

        if ($exitCode -ne 0) {
            throw "Vivado failed with exit code $exitCode. See log: $log"
        }
    }

    Require-File -Path $StableBit -Name "stable bitstream"
    Require-File -Path $TimingRpt -Name "timing report"
    Require-File -Path $TclSummary -Name "TCL summary"

    $stableItem = Get-Item -LiteralPath $StableBit
    $namedItem = Get-LatestNamedBit -Root $Root
    $sha256 = (Get-FileHash -LiteralPath $StableBit -Algorithm SHA256).Hash
    $kv = Get-KeyValueFile -Path $TclSummary
    $timing = Get-DesignTimingSummary -Path $TimingRpt

    $wnsNumber = $null
    $timingClean = "UNKNOWN"
    if ([double]::TryParse($timing.WNS, [ref]$wnsNumber)) {
        $timingClean = if ($wnsNumber -ge 0.0 -and $timing.FailingEndpoints -eq "0") { "YES" } else { "NO" }
    }

    $summaryLines = @(
        "IMPL_STRATEGY=Performance_Explore",
        "RESET_SYNTH=$(if ($SkipSynthesis) { 'NO' } else { 'YES' })",
        "BIT_STABLE=$StableBit",
        "BIT_NAMED=$(if ($namedItem) { $namedItem.FullName } else { '' })",
        "BIT_MTIME=$($stableItem.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))",
        "BIT_SHA256=$sha256",
        "TIMING_REPORT=$TimingRpt",
        "PATHS_REPORT=$PathsRpt",
        "TCL_SUMMARY=$TclSummary",
        "WNS=$($timing.WNS)",
        "TNS=$($timing.TNS)",
        "FAILING_ENDPOINTS=$($timing.FailingEndpoints)",
        "WORST_SETUP_SLACK=$($kv['WORST_SETUP_SLACK'])",
        "WORST_SETUP_SOURCE=$($kv['WORST_SETUP_SOURCE'])",
        "WORST_SETUP_DESTINATION=$($kv['WORST_SETUP_DESTINATION'])",
        "TIMING_CLEAN=$timingClean"
    )

    $summaryLines | Set-Content -LiteralPath $PsSummary -Encoding UTF8

    Write-Host ""
    Write-Host "=== Performance_Explore bit build summary ==="
    $summaryLines | ForEach-Object { Write-Host $_ }
    Write-Host "PS_SUMMARY=$PsSummary"
}
finally {
    Pop-Location
}
