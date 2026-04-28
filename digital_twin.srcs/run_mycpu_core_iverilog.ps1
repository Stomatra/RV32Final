param (
    [string]$Tb = 'sim_1\new\tb_myCPU_core.sv',
    [string]$IromCoe = 'sources_1\imports\test_src\irom.coe',
    [string]$DramCoe = 'sources_1\imports\test_src\dram.coe',
    [string]$OutDir = 'sim_iverilog_core',
    [int]$TimeoutNs = 10000000,
    [switch]$Clean,
    [switch]$NoRun,
    [switch]$NoWaveform,
    [switch]$OpenWaveform,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

function Resolve-RepoPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$BaseDir = $ScriptDir
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        if (-not (Test-Path $Path)) {
            throw "Path not found: $Path"
        }
        return (Resolve-Path $Path).Path
    }

    $candidate = Join-Path $BaseDir $Path
    if (-not (Test-Path $candidate)) {
        throw "Path not found: $Path"
    }
    return (Resolve-Path $candidate).Path
}

function Convert-CoeToMem {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestPath,
        [string]$DefaultWord = '00000000',
        [int]$ExpectedWords = 0
    )

    $raw = Get-Content $SourcePath -Raw
    $match = [regex]::Match($raw, '(?is)memory_initialization_vector\s*=\s*(.+?);')
    if (-not $match.Success) {
        throw "Invalid COE file: $SourcePath"
    }

    $tokens = $match.Groups[1].Value -split '[,\s]+' |
        Where-Object { $_ -and ($_ -match '^[0-9a-fA-F]+$') }

    if ($tokens.Count -eq 0) {
        $tokens = @($DefaultWord)
    }

    if ($ExpectedWords -gt $tokens.Count) {
        $padding = for ($i = $tokens.Count; $i -lt $ExpectedWords; $i++) {
            $DefaultWord
        }
        $tokens = @($tokens) + @($padding)
    }

    Set-Content -Path $DestPath -Value ($tokens -join [Environment]::NewLine) -Encoding ascii
}

function Escape-VerilogPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return ($Path -replace '\\', '/')
}

$tbPath = Resolve-RepoPath -Path $Tb
$importsDir = Resolve-RepoPath -Path 'sources_1\imports\new'
$iromCoePath = Resolve-RepoPath -Path $IromCoe
$dramCoePath = Resolve-RepoPath -Path $DramCoe

$outDirAbs = if ([System.IO.Path]::IsPathRooted($OutDir)) {
    $OutDir
} else {
    Join-Path $ScriptDir $OutDir
}

$buildDir = Join-Path $outDirAbs 'build'
$generatedDir = Join-Path $buildDir 'generated'

if ($Clean -and (Test-Path $outDirAbs)) {
    Remove-Item $outDirAbs -Recurse -Force
}

foreach ($dir in @($outDirAbs, $buildDir, $generatedDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
}

$tbModuleMatch = Select-String -Path $tbPath -Pattern '^\s*module\s+([A-Za-z_][A-Za-z0-9_]*)' | Select-Object -First 1
if (-not $tbModuleMatch) {
    throw "Cannot find testbench module name in $tbPath"
}

$tbModule = $tbModuleMatch.Matches[0].Groups[1].Value
$iromMemPath = Join-Path $generatedDir 'irom.mem'
$dramMemPath = Join-Path $generatedDir 'dram.mem'
$vvpPath = Join-Path $buildDir "$tbModule.vvp"
$vcdPath = Join-Path $outDirAbs "$tbModule.vcd"

Convert-CoeToMem -SourcePath $iromCoePath -DestPath $iromMemPath -DefaultWord '00000013' -ExpectedWords 4096
Convert-CoeToMem -SourcePath $dramCoePath -DestPath $dramMemPath -DefaultWord '00000000' -ExpectedWords 65536

$sourceFiles = @(
    (Resolve-RepoPath -Path 'sources_1\imports\new\myCPU.sv'),
    (Resolve-RepoPath -Path 'sources_1\imports\new\IMMGEN.sv'),
    (Resolve-RepoPath -Path 'sources_1\imports\new\RF.sv'),
    (Resolve-RepoPath -Path 'sources_1\imports\new\ALU.sv'),
    (Resolve-RepoPath -Path 'sources_1\imports\new\NPC.sv'),
    $tbPath
)

if (Test-Path $vvpPath) {
    Remove-Item $vvpPath -Force
}

$iverilogArgs = @(
    '-g2012',
    '-o', $vvpPath,
    '-s', $tbModule,
    '-I', $importsDir
) + $sourceFiles

Write-Host '=============================================='
Write-Host " TB      : $tbModule"
Write-Host " TB File : $tbPath"
Write-Host " IROM    : $iromCoePath"
Write-Host " DRAM    : $dramCoePath"
Write-Host '=============================================='
Write-Host ''
Write-Host '[INFO] Compiling with iverilog...'

& iverilog @iverilogArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host '[ERROR] Compilation failed.'
    exit 1
}

Write-Host '[INFO] Compilation OK'

if ($NoRun) {
    Write-Host '[INFO] Skipping simulation run because -NoRun was provided.'
    exit 0
}

$vvpArgs = @(
    $vvpPath,
    ('+irom={0}' -f (Escape-VerilogPath $iromMemPath)),
    ('+dram={0}' -f (Escape-VerilogPath $dramMemPath)),
    ('+timeout_ns={0}' -f $TimeoutNs)
)

if (-not $NoWaveform) {
    $vvpArgs += ('+vcd={0}' -f (Escape-VerilogPath $vcdPath))
}

if ($Verbose) {
    $vvpArgs += '+verbose'
}

Write-Host '[INFO] Running simulation...'
& vvp -n @vvpArgs
$simExitCode = $LASTEXITCODE

if ($simExitCode -ne 0) {
    Write-Host "[ERROR] Simulation failed with exit code $simExitCode"
    exit $simExitCode
}

Write-Host '[INFO] Simulation completed.'

if ((-not $NoWaveform) -and (Test-Path $vcdPath)) {
    Write-Host "[INFO] Waveform: $vcdPath"
    if ($OpenWaveform -and (Get-Command gtkwave -ErrorAction SilentlyContinue)) {
        Start-Process gtkwave $vcdPath
    }
}

exit 0