param (
    [string]$Tb = 'tb_myCPU.sv',
    [string]$IromCoe = 'sources_1\imports\test_src\irom.coe',
    [string]$DramCoe = 'sources_1\imports\test_src\dram.coe',
    [string]$OutDir = 'sim_iverilog',
    [int]$StopTimeNs = 10000000,
    [switch]$Clean,
    [switch]$NoRun,
    [switch]$NoWaveform,
    [switch]$OpenWaveform
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

        [string]$DefaultWord = '00000000'
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

    Set-Content -Path $DestPath -Value ($tokens -join [Environment]::NewLine) -Encoding ascii
}

function Escape-VerilogPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return ($Path -replace '\\', '/')
}

if (-not [System.IO.Path]::GetExtension($Tb)) {
    $Tb = "$Tb.sv"
}

$tbDir = Join-Path $ScriptDir 'sim_1\new'
$importsDir = Join-Path $ScriptDir 'sources_1\imports\new'
$designDir = Join-Path $ScriptDir 'sources_1\new'
$tbPath = Resolve-RepoPath -Path $Tb -BaseDir $tbDir
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
$wrapperName = '__iverilog_tb_wrapper'

$iromMemPath = Join-Path $generatedDir 'irom.mem'
$dramMemPath = Join-Path $generatedDir 'dram.mem'
$pllStubPath = Join-Path $generatedDir 'pll_iverilog_stub.sv'
$iromStubPath = Join-Path $generatedDir 'IROM_iverilog_stub.sv'
$dramStubPath = Join-Path $generatedDir 'DRAM_iverilog_stub.sv'
$wrapperPath = Join-Path $generatedDir 'tb_wrapper.sv'
$vvpPath = Join-Path $buildDir "$tbModule.vvp"
$vcdPath = Join-Path $outDirAbs "$tbModule.vcd"

Convert-CoeToMem -SourcePath $iromCoePath -DestPath $iromMemPath -DefaultWord '00000013'
Convert-CoeToMem -SourcePath $dramCoePath -DestPath $dramMemPath -DefaultWord '00000000'

$pllStub = @'
`timescale 1ns / 1ps

module pll (
    input  wire clk_in1_p,
    input  wire clk_in1_n,
    output logic clk_out1,
    output logic clk_out2,
    output logic locked
);
    logic div2;
    logic [3:0] lock_count;

    initial begin
        clk_out1 = 1'b0;
        clk_out2 = 1'b0;
        locked = 1'b0;
        div2 = 1'b0;
        lock_count = 4'd0;
    end

    always @(posedge clk_in1_p) begin
        div2 <= ~div2;
        if (div2) begin
            clk_out1 <= ~clk_out1;
            clk_out2 <= ~clk_out2;
        end

        if (!locked) begin
            lock_count <= lock_count + 1'b1;
            if (lock_count == 4'd7) begin
                locked <= 1'b1;
            end
        end
    end
endmodule
'@

$iromStub = @'
`timescale 1ns / 1ps

module IROM (
    input  wire [11:0] a,
    output logic [31:0] spo
);
    logic [31:0] mem [0:4095];
    integer idx;

    initial begin
        for (idx = 0; idx < 4096; idx = idx + 1) begin
            mem[idx] = 32'h00000013;
        end
        $readmemh("__IROM_MEM__", mem);
    end

    always @(*) begin
        spo = mem[a];
    end
endmodule
'@ -replace '__IROM_MEM__', (Escape-VerilogPath $iromMemPath)

$dramStub = @'
`timescale 1ns / 1ps

module DRAM (
    input  wire        clk,
    input  wire [15:0] a,
    output logic [31:0] spo,
    input  wire        we,
    input  wire [31:0] d
);
    logic [31:0] mem [0:65535];
    integer idx;

    initial begin
        for (idx = 0; idx < 65536; idx = idx + 1) begin
            mem[idx] = 32'h00000000;
        end
        $readmemh("__DRAM_MEM__", mem);
    end

    always @(*) begin
        spo = mem[a];
    end

    always @(posedge clk) begin
        if (we) begin
            mem[a] <= d;
        end
    end
endmodule
'@ -replace '__DRAM_MEM__', (Escape-VerilogPath $dramMemPath)

$waveformLines = @()
if (-not $NoWaveform) {
    $waveformLines += ('        $dumpfile("{0}");' -f (Escape-VerilogPath $vcdPath))
    $waveformLines += '        $dumpvars(0, dut);'
}

$wrapperBody = @(
    '`timescale 1ns / 1ps',
    '',
    "module $wrapperName;",
    "    $tbModule dut();",
    '    initial begin'
)
$wrapperBody += $waveformLines
$wrapperBody += @(
    "        #$StopTimeNs;",
    '        $display("[SIM] Timeout reached at %0t ns", $time);',
    '        $finish;',
    '    end',
    'endmodule'
)

Set-Content -Path $pllStubPath -Value $pllStub -Encoding ascii
Set-Content -Path $iromStubPath -Value $iromStub -Encoding ascii
Set-Content -Path $dramStubPath -Value $dramStub -Encoding ascii
Set-Content -Path $wrapperPath -Value ($wrapperBody -join [Environment]::NewLine) -Encoding ascii

$designFileNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
Get-ChildItem $designDir -File | ForEach-Object {
    [void]$designFileNames.Add($_.Name)
}

$sourceFiles = @(
    (Get-ChildItem $importsDir -File |
        Where-Object { $_.Extension -in '.sv', '.v' -and -not $designFileNames.Contains($_.Name) } |
        Sort-Object FullName |
        ForEach-Object { $_.FullName }),
    (Get-ChildItem $designDir -File | Where-Object { $_.Extension -in '.sv', '.v' } | Sort-Object FullName | ForEach-Object { $_.FullName }),
    $tbPath,
    $pllStubPath,
    $iromStubPath,
    $dramStubPath,
    $wrapperPath
) | ForEach-Object { $_ }

if (Test-Path $vvpPath) {
    Remove-Item $vvpPath -Force
}

$iverilogArgs = @(
    '-g2012',
    '-o', $vvpPath,
    '-s', $wrapperName,
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

Write-Host '[INFO] Running simulation...'
& vvp -n $vvpPath
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