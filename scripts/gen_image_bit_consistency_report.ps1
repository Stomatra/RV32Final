Set-Location 'e:\Projects\1Aprojects\RV32Final'
$ErrorActionPreference = 'Continue'

function Add-MetaLine([string]$label, [string]$path) {
    if (-not $path -or -not (Test-Path $path)) {
        return "[$label] MISSING path=$path"
    }
    $it = Get-Item $path
    $h = (Get-FileHash $path -Algorithm SHA256).Hash
    return "[$label] path=$($it.FullName) | size=$($it.Length) | mtime=$($it.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')) | sha256=$h"
}

$report = New-Object System.Collections.Generic.List[string]
$report.Add("report_time=" + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'))

$iromMem = (Resolve-Path '.\digital_twin.srcs\sim_iverilog\build\generated\irom.mem' -ErrorAction SilentlyContinue).Path
$dramMem = (Resolve-Path '.\digital_twin.srcs\sim_iverilog\build\generated\dram.mem' -ErrorAction SilentlyContinue).Path
$iromXci = (Resolve-Path '.\digital_twin.srcs\sources_1\ip\IROM\IROM.xci' -ErrorAction SilentlyContinue).Path
$dramXci = (Resolve-Path '.\digital_twin.srcs\sources_1\ip\DRAM\DRAM.xci' -ErrorAction SilentlyContinue).Path

$iromCoeFromXci = (Resolve-Path '.\digital_twin.srcs\sources_1\imports\test_src\irom.coe' -ErrorAction SilentlyContinue).Path
$dramCoeFromXci = (Resolve-Path '.\digital_twin.srcs\sources_1\imports\test_src\dram.coe' -ErrorAction SilentlyContinue).Path

$report.Add((Add-MetaLine 'SIM_IROM_MEM' $iromMem))
$report.Add((Add-MetaLine 'SIM_DRAM_MEM' $dramMem))
$report.Add((Add-MetaLine 'XCI_IROM' $iromXci))
$report.Add((Add-MetaLine 'XCI_DRAM' $dramXci))
$report.Add((Add-MetaLine 'XCI_REF_IROM_COE' $iromCoeFromXci))
$report.Add((Add-MetaLine 'XCI_REF_DRAM_COE' $dramCoeFromXci))

$memInitFiles = Get-ChildItem '.\digital_twin.ip_user_files\mem_init_files' -File -ErrorAction SilentlyContinue | Sort-Object Name
foreach ($f in $memInitFiles) {
    $report.Add((Add-MetaLine ('IP_USER_MEM_INIT_' + $f.Name) $f.FullName))
}

$implBit = (Resolve-Path '.\digital_twin.runs\impl_1\top.bit' -ErrorAction SilentlyContinue).Path
$report.Add((Add-MetaLine 'IMPL1_TOP_BIT' $implBit))

$programBits = @(
    '.\top_normal.bit',
    '.\top_normal_best.bit',
    '.\top.bit',
    '.\top_ila.bit',
    '.\top_normal_timing_clean.bit',
    '.\top_normal_postroute_physopt.bit'
)
foreach ($p in $programBits) {
    $rp = (Resolve-Path $p -ErrorAction SilentlyContinue).Path
    if ($rp) {
        $report.Add((Add-MetaLine ('PROGRAM_BIT_' + [IO.Path]::GetFileName($rp)) $rp))
    }
}

if ($iromMem -and $iromCoeFromXci) {
    $simIromHash = (Get-FileHash $iromMem -Algorithm SHA256).Hash
    $coeIromHash = (Get-FileHash $iromCoeFromXci -Algorithm SHA256).Hash
    $report.Add('COMPARE sim_irom_mem_vs_xci_irom_coe_sha256_equal=' + ($simIromHash -eq $coeIromHash))
}
if ($dramMem -and $dramCoeFromXci) {
    $simDramHash = (Get-FileHash $dramMem -Algorithm SHA256).Hash
    $coeDramHash = (Get-FileHash $dramCoeFromXci -Algorithm SHA256).Hash
    $report.Add('COMPARE sim_dram_mem_vs_xci_dram_coe_sha256_equal=' + ($simDramHash -eq $coeDramHash))
}

$report.Add('NOTE rebuild_status=forced reset/generate commands executed; synth_1 currently failing due unresolved module pll in project run flow')
$report.Add('NOTE rebuild_logs=rebuild_for_image_consistency.log;rebuild_consistency_full.log;rebuild_consistency_fix_pll.log')

$reportPath = '.\image_bit_consistency_report.txt'
$report | Set-Content -Path $reportPath -Encoding UTF8
Write-Output ('report_saved=' + (Resolve-Path $reportPath).Path)
Get-Content $reportPath
