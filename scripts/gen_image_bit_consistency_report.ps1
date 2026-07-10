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

function Get-NormalizedSha256([string[]]$words) {
    $joined = [string]::Join("`n", $words)
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($joined)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($bytes)
        return -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    } finally {
        $sha.Dispose()
    }
}

function Convert-ToWordHex([UInt64]$value) {
    return ('{0:X8}' -f ([UInt32]($value -band 0xFFFFFFFF)))
}

function Get-WordsFromMem([string]$path) {
    $text = Get-Content -Raw -Path $path
    $text = [Regex]::Replace($text, '//.*?$', '', [Text.RegularExpressions.RegexOptions]::Multiline)
    $text = [Regex]::Replace($text, '#.*?$', '', [Text.RegularExpressions.RegexOptions]::Multiline)
    $tokens = $text -split '[,;\s]+'
    $words = New-Object System.Collections.Generic.List[string]
    foreach ($tokRaw in $tokens) {
        $tok = $tokRaw.Trim()
        if (-not $tok) { continue }
        if ($tok.StartsWith('@')) { continue }
        if ($tok -match '^[0-9A-Fa-f]+$') {
            $v = [Convert]::ToUInt64($tok, 16)
            $words.Add((Convert-ToWordHex $v))
        }
    }
    return ,$words.ToArray()
}

function Get-WordsFromCoe([string]$path) {
    $text = Get-Content -Raw -Path $path
    $text = [Regex]::Replace($text, '//.*?$', '', [Text.RegularExpressions.RegexOptions]::Multiline)
    $radix = 16
    $mRadix = [Regex]::Match($text, '(?im)memory_initialization_radix\s*=\s*(\d+)\s*;')
    if ($mRadix.Success) {
        $radix = [int]$mRadix.Groups[1].Value
    }

    $mVec = [Regex]::Match($text, '(?is)memory_initialization_vector\s*=\s*(.+?)\s*;')
    if (-not $mVec.Success) {
        throw "COE parse failed: memory_initialization_vector not found in $path"
    }
    $vecText = $mVec.Groups[1].Value
    $tokens = $vecText -split '[,;\s]+'

    $words = New-Object System.Collections.Generic.List[string]
    foreach ($tokRaw in $tokens) {
        $tok = $tokRaw.Trim()
        if (-not $tok) { continue }
        $tok = $tok -replace '_', ''
        if ($radix -eq 16) {
            if ($tok -notmatch '^[0-9A-Fa-f]+$') { continue }
            $v = [Convert]::ToUInt64($tok, 16)
        } elseif ($radix -eq 10) {
            if ($tok -notmatch '^[0-9]+$') { continue }
            $v = [Convert]::ToUInt64($tok, 10)
        } else {
            throw "Unsupported COE radix=$radix in $path"
        }
        $words.Add((Convert-ToWordHex $v))
    }
    return ,$words.ToArray()
}

function Find-FirstMismatch([string[]]$leftWords, [string[]]$rightWords) {
    $n = [Math]::Min($leftWords.Count, $rightWords.Count)
    for ($i = 0; $i -lt $n; $i++) {
        if ($leftWords[$i] -ne $rightWords[$i]) {
            return $i
        }
    }
    if ($leftWords.Count -ne $rightWords.Count) {
        return $n
    }
    return -1
}

function Sample-Words([string[]]$words, [int]$count, [bool]$tail) {
    if ($words.Count -eq 0) { return '' }
    if ($words.Count -le $count) {
        return ($words -join ' ')
    }
    if ($tail) {
        return ($words[($words.Count - $count)..($words.Count - 1)] -join ' ')
    }
    return ($words[0..($count - 1)] -join ' ')
}

function Add-WordCompareSection(
    [System.Collections.Generic.List[string]]$report,
    [string]$name,
    [string]$memPath,
    [string]$coePath
) {
    if (-not $memPath -or -not $coePath -or -not (Test-Path $memPath) -or -not (Test-Path $coePath)) {
        $report.Add("COMPARE_WORDS $name missing_input mem=$memPath coe=$coePath")
        return
    }

    try {
        $memWords = Get-WordsFromMem $memPath
        $coeWords = Get-WordsFromCoe $coePath
        $memSha = Get-NormalizedSha256 $memWords
        $coeSha = Get-NormalizedSha256 $coeWords
        $equal = ($memSha -eq $coeSha)

        $report.Add("COMPARE_WORDS $name count_mem=$($memWords.Count) count_coe=$($coeWords.Count) norm_sha_mem=$memSha norm_sha_coe=$coeSha equal=$equal")
        $report.Add("COMPARE_WORDS $name mem_first32=$(Sample-Words $memWords 32 $false)")
        $report.Add("COMPARE_WORDS $name coe_first32=$(Sample-Words $coeWords 32 $false)")
        $report.Add("COMPARE_WORDS $name mem_last32=$(Sample-Words $memWords 32 $true)")
        $report.Add("COMPARE_WORDS $name coe_last32=$(Sample-Words $coeWords 32 $true)")

        $mismatch = Find-FirstMismatch $memWords $coeWords
        if ($mismatch -ge 0) {
            $leftVal = if ($mismatch -lt $memWords.Count) { $memWords[$mismatch] } else { '<EOF>' }
            $rightVal = if ($mismatch -lt $coeWords.Count) { $coeWords[$mismatch] } else { '<EOF>' }
            $report.Add("COMPARE_WORDS $name first_mismatch_index=$mismatch mem=$leftVal coe=$rightVal")
        } else {
            $report.Add("COMPARE_WORDS $name first_mismatch_index=-1")
        }
    } catch {
        $report.Add("COMPARE_WORDS $name error=$($_.Exception.Message)")
    }
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

Add-WordCompareSection -report $report -name 'IROM_MEM_VS_XCI_COE' -memPath $iromMem -coePath $iromCoeFromXci
Add-WordCompareSection -report $report -name 'DRAM_MEM_VS_XCI_COE' -memPath $dramMem -coePath $dramCoeFromXci

$report.Add('NOTE compare_mode=normalized_32bit_word_list_sha256')
$report.Add('NOTE rebuild_logs=rebuild_bit_fix_pll_refs.log')

$reportPath = '.\image_bit_consistency_report.txt'
$report | Set-Content -Path $reportPath -Encoding UTF8
Write-Output ('report_saved=' + (Resolve-Path $reportPath).Path)
Get-Content $reportPath
