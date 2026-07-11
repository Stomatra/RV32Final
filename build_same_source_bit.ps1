# build_same_source_bit.ps1
# 用于同源重建 bit：复制指定 irom/dram -> 清宏 -> 重建 IP -> Performance_Explore 实现 -> 导出 bit/hash/timing

param(
    [string]$ProjectRoot = "E:\Projects\1Aprojects\RV32Final",
    [string]$IromCoe     = "E:\jyd2026\withoutMext\demo\irom-v2.coe",
    [string]$DramCoe     = "E:\jyd2026\withoutMext\demo\dram.coe",
    [string]$Tag         = "withoutmext_irom_v2_150m_normal_rebuild",
    [int]$Jobs           = 8
)

$ErrorActionPreference = "Stop"

# 1. 基本路径
$Xpr = Join-Path $ProjectRoot "digital_twin.xpr"
$ImportDir = Join-Path $ProjectRoot "digital_twin.srcs\sources_1\imports\test_src"
$DstIrom = Join-Path $ImportDir "irom.coe"
$DstDram = Join-Path $ImportDir "dram.coe"

$OutDir = Join-Path $ProjectRoot "build_outputs"
$TclPath = Join-Path $OutDir "build_$Tag.tcl"
$TimingRpt = Join-Path $OutDir "timing_$Tag.rpt"
$OutBit = Join-Path $OutDir "top_$Tag.bit"

New-Item -ItemType Directory -Force -Path $ImportDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (!(Test-Path $Xpr)) {
    throw "找不到 Vivado 工程: $Xpr"
}
if (!(Test-Path $IromCoe)) {
    throw "找不到 IROM COE: $IromCoe"
}

# 2. 复制 IROM / DRAM
Copy-Item -Force $IromCoe $DstIrom
Write-Host "Copied IROM:"
Write-Host "  $IromCoe"
Write-Host "-> $DstIrom"

if (Test-Path $DramCoe) {
    Copy-Item -Force $DramCoe $DstDram
    Write-Host "Copied DRAM:"
    Write-Host "  $DramCoe"
    Write-Host "-> $DstDram"
} else {
    Write-Host "DRAM COE 不存在，跳过复制: $DramCoe"
}

# 3. 删除常见旧 MIF 缓存，避免误判
$MaybeOldMifs = @(
    (Join-Path $ProjectRoot "digital_twin.gen\sources_1\ip\IROM\IROM.mif")
    (Join-Path $ProjectRoot "digital_twin.gen\sources_1\ip\DRAM\DRAM.mif")
    (Join-Path $ProjectRoot "digital_twin.ip_user_files\mem_init_files\IROM.mif")
    (Join-Path $ProjectRoot "digital_twin.ip_user_files\mem_init_files\DRAM.mif")
)

foreach ($f in $MaybeOldMifs) {
    if (Test-Path $f) {
        Remove-Item -Force $f
        Write-Host "Removed old cache: $f"
    }
}

function Convert-ToTclPath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

$ProjectRootTcl = Convert-ToTclPath $ProjectRoot
$XprTcl         = Convert-ToTclPath $Xpr
$OutDirTcl      = Convert-ToTclPath $OutDir
$OutBitTcl      = Convert-ToTclPath $OutBit
$TimingRptTcl   = Convert-ToTclPath $TimingRpt

# 4. 生成 Tcl
$tcl = @"
set project_root [file normalize {$ProjectRootTcl}]
set xpr          [file normalize {$XprTcl}]
set out_dir      [file normalize {$OutDirTcl}]
set out_bit      [file normalize {$OutBitTcl}]
set timing_rpt   [file normalize {$TimingRptTcl}]
set jobs         $Jobs

puts "Opening project: `$xpr"
open_project `$xpr

# 清除所有调试宏，避免 DEBUG_HW_MILESTONE / LED_WALK_TEST 残留
set fs [get_filesets sources_1]
set_property verilog_define {} `$fs
puts "sources_1 verilog_define = [get_property verilog_define `$fs]"

# 更新 compile order
update_compile_order -fileset sources_1

# 重新生成 IP output products
puts "Regenerating IP output products..."
foreach ip [get_ips] {
    puts "generate_target all `$ip"
    generate_target all `$ip
}

# 重跑所有 IP synth run
set ip_runs [get_runs *_synth_1]
if {[llength `$ip_runs] > 0} {
    foreach r `$ip_runs {
        catch { reset_run `$r }
    }
    launch_runs `$ip_runs -jobs `$jobs
    foreach r `$ip_runs {
        wait_on_run `$r
    }
}

# 重新综合
puts "Reset synth_1..."
catch { reset_run synth_1 }
launch_runs synth_1 -jobs `$jobs
wait_on_run synth_1

# 设置实现策略
puts "Set impl_1 strategy Performance_Explore..."
set_property strategy Performance_Explore [get_runs impl_1]

# 打开 phys_opt，进一步稳住 timing
catch {
    set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
    set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
}

# 重新实现并写 bit
puts "Reset impl_1..."
catch { reset_run impl_1 }
launch_runs impl_1 -to_step write_bitstream -jobs `$jobs
wait_on_run impl_1

open_run impl_1

# 导出 timing
report_timing_summary -file `$timing_rpt -delay_type max -report_unconstrained -check_timing_verbose

# 复制 bit
set impl_bit [file normalize [file join `$project_root "digital_twin.runs" "impl_1" "top.bit"]]
if {![file exists `$impl_bit]} {
    error "Cannot find generated bit: `$impl_bit"
}

file copy -force `$impl_bit `$out_bit

puts "BIT_OUT=`$out_bit"
puts "TIMING_RPT=`$timing_rpt"
puts "Build finished."
close_project
"@

$Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[System.IO.File]::WriteAllText($TclPath, $tcl, $Utf8NoBom)
Write-Host "Generated Tcl: $TclPath"

# 5. 启动 Vivado
$VivadoCmd = "vivado"
Write-Host "Running Vivado..."
& $VivadoCmd -mode batch -source $TclPath

if ($LASTEXITCODE -ne 0) {
    throw "Vivado build failed, exit code = $LASTEXITCODE"
}

# 6. 输出 hash / 时间
if (!(Test-Path $OutBit)) {
    throw "没有生成目标 bit: $OutBit"
}

$BitHash = Get-FileHash -Algorithm SHA256 $OutBit
$BitItem = Get-Item $OutBit

Write-Host ""
Write-Host "========================================"
Write-Host "Build OK"
Write-Host "BIT: $OutBit"
Write-Host "MTime: $($BitItem.LastWriteTime)"
Write-Host "Size: $($BitItem.Length) bytes"
Write-Host "SHA256: $($BitHash.Hash)"
Write-Host "Timing: $TimingRpt"
Write-Host "IROM copied to: $DstIrom"
Write-Host "IROM SHA256: $((Get-FileHash -Algorithm SHA256 $DstIrom).Hash)"
if (Test-Path $DstDram) {
    Write-Host "DRAM copied to: $DstDram"
    Write-Host "DRAM SHA256: $((Get-FileHash -Algorithm SHA256 $DstDram).Hash)"
}
Write-Host "========================================"
