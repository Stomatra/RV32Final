param(
    [string]$CoePath = "digital_twin.srcs/sources_1/imports/test_src/irom.coe",
    [string]$OutDisasmPath = "analysis/test_src_irom_disasm_with_pc.txt",
    [string]$OutReportPath = "analysis/led_mmio_80200040_report.txt",
    [string]$LedMmioAddr = "0x80200040",
    [string]$BasePc = "0x80000000",
    [int]$ContextWindow = 30
)

$ErrorActionPreference = 'Stop'

if ($BasePc -is [string]) {
    if ($BasePc.StartsWith("0x") -or $BasePc.StartsWith("0X")) {
        $BasePc = [Convert]::ToUInt32($BasePc.Substring(2), 16)
    } else {
        $BasePc = [Convert]::ToUInt32($BasePc, 10)
    }
}

if ($LedMmioAddr -is [string]) {
    if ($LedMmioAddr.StartsWith("0x") -or $LedMmioAddr.StartsWith("0X")) {
        $LedMmioAddr = [Convert]::ToUInt32($LedMmioAddr.Substring(2), 16)
    } else {
        $LedMmioAddr = [Convert]::ToUInt32($LedMmioAddr, 10)
    }
}

function Get-Bits([uint32]$v, [int]$hi, [int]$lo) {
    return (($v -shr $lo) -band ((1 -shl ($hi - $lo + 1)) - 1))
}

function Sign-Extend([int64]$v, [int]$bits) {
    $sign = 1 -shl ($bits - 1)
    if (($v -band $sign) -ne 0) {
        return ($v -bor (-1 -bxor ((1 -shl $bits) - 1)))
    }
    return $v
}

function Wrap-U32([int64]$v) {
    $m = $v % 4294967296
    if ($m -lt 0) { $m += 4294967296 }
    return [uint32]$m
}

function To-Hex32([uint32]$v) {
    return ('0x{0:X8}' -f $v)
}

function Parse-CoeWords([string]$path) {
    $txt = Get-Content -Raw -Path $path
    $txt = [Regex]::Replace($txt, '//.*?$', '', [Text.RegularExpressions.RegexOptions]::Multiline)

    $mRadix = [Regex]::Match($txt, '(?im)memory_initialization_radix\s*=\s*(\d+)\s*;')
    if (-not $mRadix.Success) {
        throw "COE missing memory_initialization_radix: $path"
    }
    $radix = [int]$mRadix.Groups[1].Value
    if ($radix -ne 16 -and $radix -ne 10) {
        throw "Unsupported COE radix=$radix in $path"
    }

    $mVec = [Regex]::Match($txt, '(?is)memory_initialization_vector\s*=\s*(.+?)\s*;')
    if (-not $mVec.Success) {
        throw "COE missing memory_initialization_vector: $path"
    }

    $tokens = $mVec.Groups[1].Value -split '[,;\s]+'
    $words = New-Object System.Collections.Generic.List[uint32]
    foreach ($raw in $tokens) {
        $t = $raw.Trim() -replace '_',''
        if (-not $t) { continue }
        if ($radix -eq 16) {
            if ($t -notmatch '^[0-9A-Fa-f]+$') { continue }
            $v = [Convert]::ToUInt64($t, 16)
        } else {
            if ($t -notmatch '^[0-9]+$') { continue }
            $v = [Convert]::ToUInt64($t, 10)
        }
        $words.Add([uint32]($v -band 0xFFFFFFFF))
    }
    return ,$words.ToArray()
}

function Decode-Rv32([uint32]$pc, [uint32]$instr) {
    $opcode = Get-Bits $instr 6 0
    $rd = Get-Bits $instr 11 7
    $funct3 = Get-Bits $instr 14 12
    $rs1 = Get-Bits $instr 19 15
    $rs2 = Get-Bits $instr 24 20
    $funct7 = Get-Bits $instr 31 25

    $mn = 'unknown'
    $target = $null
    $itype = 'OTHER'

    switch ($opcode) {
        0x37 {
            $immU = (Get-Bits $instr 31 12)
            $mn = ('lui x{0},0x{1:X}' -f $rd, $immU)
            $itype = 'LUI'
        }
        0x17 {
            $immU = (Get-Bits $instr 31 12)
            $mn = ('auipc x{0},0x{1:X}' -f $rd, $immU)
            $itype = 'AUIPC'
        }
        0x6F {
            $imm = ((Get-Bits $instr 31 31) -shl 20) -bor ((Get-Bits $instr 19 12) -shl 12) -bor ((Get-Bits $instr 20 20) -shl 11) -bor ((Get-Bits $instr 30 21) -shl 1)
            $simm = [int32](Sign-Extend $imm 21)
            $target = Wrap-U32 ([int64]$pc + [int64]$simm)
            $mn = "jal x$rd,$simm"
            $itype = 'JAL'
        }
        0x67 {
            $imm = [int32](Sign-Extend (Get-Bits $instr 31 20) 12)
            $mn = "jalr x$rd,x$rs1,$imm"
            $itype = 'JALR'
        }
        0x63 {
            $imm = ((Get-Bits $instr 31 31) -shl 12) -bor ((Get-Bits $instr 7 7) -shl 11) -bor ((Get-Bits $instr 30 25) -shl 5) -bor ((Get-Bits $instr 11 8) -shl 1)
            $simm = [int32](Sign-Extend $imm 13)
            $target = Wrap-U32 ([int64]$pc + [int64]$simm)
            switch ($funct3) {
                0 { $mn = "beq x$rs1,x$rs2,$simm" }
                1 { $mn = "bne x$rs1,x$rs2,$simm" }
                4 { $mn = "blt x$rs1,x$rs2,$simm" }
                5 { $mn = "bge x$rs1,x$rs2,$simm" }
                6 { $mn = "bltu x$rs1,x$rs2,$simm" }
                7 { $mn = "bgeu x$rs1,x$rs2,$simm" }
                default { $mn = "branch? f3=$funct3" }
            }
            $itype = 'BRANCH'
        }
        0x03 {
            $imm = [int32](Sign-Extend (Get-Bits $instr 31 20) 12)
            switch ($funct3) {
                2 { $mn = "lw x$rd,$imm(x$rs1)" }
                0 { $mn = "lb x$rd,$imm(x$rs1)" }
                1 { $mn = "lh x$rd,$imm(x$rs1)" }
                4 { $mn = "lbu x$rd,$imm(x$rs1)" }
                5 { $mn = "lhu x$rd,$imm(x$rs1)" }
                default { $mn = "load? f3=$funct3" }
            }
            $itype = 'LOAD'
        }
        0x23 {
            $imm = ((Get-Bits $instr 31 25) -shl 5) -bor (Get-Bits $instr 11 7)
            $imm = [int32](Sign-Extend $imm 12)
            switch ($funct3) {
                2 { $mn = "sw x$rs2,$imm(x$rs1)" }
                0 { $mn = "sb x$rs2,$imm(x$rs1)" }
                1 { $mn = "sh x$rs2,$imm(x$rs1)" }
                default { $mn = "store? f3=$funct3" }
            }
            $itype = 'STORE'
        }
        0x13 {
            $imm = [int32](Sign-Extend (Get-Bits $instr 31 20) 12)
            switch ($funct3) {
                0 { $mn = "addi x$rd,x$rs1,$imm"; $itype = 'ADDI' }
                7 { $mn = "andi x$rd,x$rs1,$imm"; $itype = 'ANDI' }
                6 { $mn = "ori x$rd,x$rs1,$imm"; $itype = 'ORI' }
                4 { $mn = "xori x$rd,x$rs1,$imm"; $itype = 'XORI' }
                1 { $mn = "slli x$rd,x$rs1,$((Get-Bits $instr 24 20))"; $itype = 'SHIFTI' }
                5 {
                    if (($funct7 -band 0x20) -ne 0) { $mn = "srai x$rd,x$rs1,$((Get-Bits $instr 24 20))" }
                    else { $mn = "srli x$rd,x$rs1,$((Get-Bits $instr 24 20))" }
                    $itype = 'SHIFTI'
                }
                default { $mn = "op-imm? f3=$funct3" }
            }
        }
        0x33 {
            switch ($funct3) {
                0 {
                    if ($funct7 -eq 0x20) { $mn = "sub x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                    elseif ($funct7 -eq 0x01) { $mn = "mul x$rd,x$rs1,x$rs2"; $itype = 'MUL' }
                    else { $mn = "add x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                }
                1 {
                    if ($funct7 -eq 0x01) { $mn = "mulh x$rd,x$rs1,x$rs2"; $itype = 'MUL' }
                    else { $mn = "sll x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                }
                2 { $mn = "slt x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                3 { $mn = "sltu x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                4 {
                    if ($funct7 -eq 0x01) { $mn = "div x$rd,x$rs1,x$rs2"; $itype = 'DIV' }
                    else { $mn = "xor x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                }
                5 {
                    if ($funct7 -eq 0x20) { $mn = "sra x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                    else { $mn = "srl x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                }
                6 {
                    if ($funct7 -eq 0x01) { $mn = "rem x$rd,x$rs1,x$rs2"; $itype = 'DIV' }
                    else { $mn = "or x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                }
                7 {
                    if ($funct7 -eq 0x01) { $mn = "remu x$rd,x$rs1,x$rs2"; $itype = 'DIV' }
                    else { $mn = "and x$rd,x$rs1,x$rs2"; $itype = 'ALU' }
                }
                default { $mn = 'op?' }
            }
        }
        0x73 {
            if ($instr -eq 0x00000073) { $mn = 'ecall' }
            elseif ($instr -eq 0x30200073) { $mn = 'mret' }
            else {
                $csr = Get-Bits $instr 31 20
                switch ($funct3) {
                    1 { $mn = ('csrrw x{0},0x{1:X3},x{2}' -f $rd,$csr,$rs1) }
                    2 { $mn = ('csrrs x{0},0x{1:X3},x{2}' -f $rd,$csr,$rs1) }
                    3 { $mn = ('csrrc x{0},0x{1:X3},x{2}' -f $rd,$csr,$rs1) }
                    5 { $mn = ('csrrwi x{0},0x{1:X3},{2}' -f $rd,$csr,$rs1) }
                    6 { $mn = ('csrrsi x{0},0x{1:X3},{2}' -f $rd,$csr,$rs1) }
                    7 { $mn = ('csrrci x{0},0x{1:X3},{2}' -f $rd,$csr,$rs1) }
                    default { $mn = ('system f3={0} csr=0x{1:X3}' -f $funct3,$csr) }
                }
            }
            $itype = 'SYSTEM'
        }
        default {
            $mn = ('opcode=0x{0:X2} rd=x{1} rs1=x{2} rs2=x{3} f3={4} f7=0x{5:X2}' -f $opcode, $rd, $rs1, $rs2, $funct3, $funct7)
        }
    }

    return [PSCustomObject]@{
        pc = $pc
        instr = $instr
        opcode = $opcode
        rd = $rd
        rs1 = $rs1
        rs2 = $rs2
        funct3 = $funct3
        funct7 = $funct7
        text = $mn
        type = $itype
        target = $target
    }
}

function New-RegConstMap() {
    $m = @{}
    for ($i=0; $i -lt 32; $i++) { $m[$i] = $null }
    $m[0] = [uint32]0
    return $m
}

function Is-StageLikeProgress([uint32]$v) {
    # 1,3,7,15... style; or single-bit progress
    if ($v -eq 0) { return $false }
    $singleBit = (($v -band ($v - 1)) -eq 0)
    $prefixOnes = ((($v + 1) -band $v) -eq 0)
    return ($singleBit -or $prefixOnes)
}

function Guess-TestName([object[]]$ctx) {
    $txt = ($ctx | ForEach-Object { $_.text }) -join "`n"
    if ($txt -match "csrr|ecall|mret|system") { return "CSR/exception path" }
    if ($txt -match "mulh|mul\s|div\s|rem\s") { return "M-ext mul/div arithmetic stress" }
    if (($txt -match "sw\s|lw\s|lb\s|lh\s") -and ($txt -match "bne|beq|blt|bge")) { return "memory loop control (sort/CRC possible)" }
    if ($txt -match "jal\s|jalr\s") { return "function call chain segment" }
    return "generic instruction functional segment"
}

function Guess-InstructionTypes([object[]]$ctx) {
    $types = @()
    foreach ($i in $ctx) {
        if ($i.type) { $types += [string]$i.type }
    }
    $uniq = $types | Sort-Object -Unique
    return ($uniq -join ',')
}

$coeAbs = (Resolve-Path $CoePath).Path
$words = Parse-CoeWords $coeAbs

$decoded = New-Object System.Collections.Generic.List[object]
for ($idx=0; $idx -lt $words.Count; $idx++) {
    $pc = Wrap-U32 ([int64]$BasePc + [int64]($idx * 4))
    $d = Decode-Rv32 $pc $words[$idx]
    $d | Add-Member -NotePropertyName idx -NotePropertyValue $idx
    $decoded.Add($d)
}

# Label discovery from direct branch/jal targets and prologue points.
$labels = @{}
foreach ($ins in $decoded) {
    if (($ins.type -eq 'JAL' -or $ins.type -eq 'BRANCH') -and $ins.target -ne $null) {
        $labels[$ins.target] = ('L_{0:X8}' -f $ins.target)
    }
}
foreach ($ins in $decoded) {
    if ($ins.type -eq 'ADDI' -and $ins.rd -eq 2 -and $ins.rs1 -eq 2) {
        # stack frame allocate near function entry heuristic
        if ($ins.text -match 'addi x2,x2,-') {
            if (-not $labels.ContainsKey($ins.pc)) {
                $labels[$ins.pc] = ('FUNC_{0:X8}' -f $ins.pc)
            }
        }
    }
}

# Emit full disasm with labels.
$disasmLines = New-Object System.Collections.Generic.List[string]
$disasmLines.Add("# source_coe=$coeAbs")
$disasmLines.Add("# words=$($words.Count) base_pc=$(To-Hex32 $BasePc)")
foreach ($ins in $decoded) {
    if ($labels.ContainsKey($ins.pc)) {
        $disasmLines.Add("")
        $disasmLines.Add(("{0}:" -f $labels[$ins.pc]))
    }
    $line = ('PC={0} INSTR={1}  {2}' -f (To-Hex32 $ins.pc), (To-Hex32 $ins.instr), $ins.text)
    if ($ins.target -ne $null) {
        $t = To-Hex32 $ins.target
        $line += ('  ; target={0}' -f $t)
        if ($labels.ContainsKey($ins.target)) {
            $line += (' ({0})' -f $labels[$ins.target])
        }
    }
    $disasmLines.Add($line)
}

$disasmDir = Split-Path -Parent $OutDisasmPath
if ($disasmDir -and -not (Test-Path $disasmDir)) { New-Item -ItemType Directory -Force -Path $disasmDir | Out-Null }
$disasmLines | Set-Content -Encoding UTF8 -Path $OutDisasmPath

# Constant tracking for LED MMIO detection.
$regConst = New-RegConstMap
$events = New-Object System.Collections.Generic.List[object]

for ($i=0; $i -lt $decoded.Count; $i++) {
    $ins = $decoded[$i]

    # Detect sw to 0x80200040 via known base+imm.
    if ($ins.opcode -eq 0x23 -and $ins.funct3 -eq 2) {
        $imm = ((Get-Bits $ins.instr 31 25) -shl 5) -bor (Get-Bits $ins.instr 11 7)
        $imm = [int32](Sign-Extend $imm 12)
        $base = $regConst[$ins.rs1]
        if ($null -ne $base) {
            $addr = Wrap-U32 ([int64]$base + [int64]$imm)
            if ($addr -eq $LedMmioAddr) {
                $wdata = $regConst[$ins.rs2]
                $bitText = 'unknown'
                if ($null -ne $wdata) {
                    $bits = New-Object System.Collections.Generic.List[string]
                    for ($b=0; $b -lt 32; $b++) {
                        if ((($wdata -shr $b) -band 1) -eq 1) { $bits.Add("bit$b") }
                    }
                    if ($bits.Count -gt 0) { $bitText = ($bits -join '|') } else { $bitText = 'none' }
                }

                $start = [Math]::Max(0, $i - $ContextWindow)
                $end = [Math]::Min($decoded.Count - 1, $i + $ContextWindow)
                $ctx = @($decoded[$start..$end])

                # Segment/function guess: nearest preceding label.
                $seg = 'unknown_segment'
                for ($k=$i; $k -ge 0; $k--) {
                    $pcTry = $decoded[$k].pc
                    if ($labels.ContainsKey($pcTry)) {
                        $seg = $labels[$pcTry]
                        break
                    }
                }

                $wdataHex = 'unknown'
                if ($null -ne $wdata) {
                    $wdataHex = To-Hex32 $wdata
                }

                $events.Add([PSCustomObject]@{
                    Index = $events.Count
                    Pc = $ins.pc
                    PcHex = (To-Hex32 $ins.pc)
                    Wdata = $wdata
                    WdataHex = $wdataHex
                    LitBits = $bitText
                    Segment = $seg
                    Context = $ctx
                    TestGuess = (Guess-TestName $ctx)
                    TypeSet = (Guess-InstructionTypes $ctx)
                    Range = ('{0}..{1}' -f (To-Hex32 $decoded[$start].pc), (To-Hex32 $decoded[$end].pc))
                })
            }
        }
    }

    # Update constant map after detection at this PC.
    $rd = $ins.rd
    if ($rd -eq 0) {
        $regConst[0] = [uint32]0
        continue
    }

    switch ($ins.opcode) {
        0x37 {
            $immU = (Get-Bits $ins.instr 31 12)
            $regConst[$rd] = Wrap-U32 ([int64]$immU -shl 12)
        }
        0x17 {
            $immU = (Get-Bits $ins.instr 31 12)
            $regConst[$rd] = Wrap-U32 ([int64]$ins.pc + ([int64]$immU -shl 12))
        }
        0x13 {
            if ($ins.funct3 -eq 0) {
                $imm = [int32](Sign-Extend (Get-Bits $ins.instr 31 20) 12)
                $src = $regConst[$ins.rs1]
                if ($null -ne $src) {
                    $regConst[$rd] = Wrap-U32 ([int64]$src + [int64]$imm)
                } else {
                    $regConst[$rd] = $null
                }
            } else {
                $regConst[$rd] = $null
            }
        }
        default {
            if ($rd -ne 0) {
                # Most instructions overwrite rd with non-constant in this simple model.
                if ($ins.opcode -ne 0x23 -and $ins.opcode -ne 0x63) {
                    $regConst[$rd] = $null
                }
            }
        }
    }
    $regConst[0] = [uint32]0
}

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add("source_coe=$coeAbs")
$reportLines.Add("disasm_file=$OutDisasmPath")
$reportLines.Add(("led_mmio_addr={0}" -f (To-Hex32 $LedMmioAddr)))
$reportLines.Add("events_found=$($events.Count)")
$reportLines.Add('')

$reportLines.Add('==== Stage Table ====')
$reportLines.Add('LED进度值 | 写入PC | 测试名称推测 | 失败前/后关键PC范围 | 相关指令类型')
foreach ($e in $events) {
    $progress = 'unknown'
    if ($e.WdataHex -ne 'unknown') {
        $progress = $e.WdataHex
    }
    $reportLines.Add(('{0} | {1} | {2} | {3} | {4}' -f $progress, $e.PcHex, $e.TestGuess, $e.Range, $e.TypeSet))
}
$reportLines.Add('')

$reportLines.Add('==== LED Write Details ====')
foreach ($e in $events) {
    $reportLines.Add(('[Event {0}]' -f $e.Index))
    $reportLines.Add(('PC={0}' -f $e.PcHex))
    $reportLines.Add(('wdata={0}' -f $e.WdataHex))
    $reportLines.Add(('点亮bit={0}' -f $e.LitBits))
    $reportLines.Add(('所在函数/代码段(推测)={0}' -f $e.Segment))
    $reportLines.Add(('测试名称推测={0}' -f $e.TestGuess))
    if ($e.WdataHex -eq '0x00000020' -or $e.WdataHex -eq '0x00000040') {
        $reportLines.Add('*** FOCUS(bit5/bit6 candidate) ***')
    }
    $reportLines.Add('--- context (prev+next 30) ---')
    foreach ($c in $e.Context) {
        $mark = if ($c.pc -eq $e.Pc) { '>>' } else { '  ' }
        $line = ('{0} PC={1} INSTR={2}  {3}' -f $mark, (To-Hex32 $c.pc), (To-Hex32 $c.instr), $c.text)
        if ($c.target -ne $null) { $line += (' ; target={0}' -f (To-Hex32 $c.target)) }
        $reportLines.Add($line)
    }
    $reportLines.Add('')
}

# bit5/bit6 summary
$bit5 = @($events | Where-Object { $_.WdataHex -eq '0x00000020' })
$bit6 = @($events | Where-Object { $_.WdataHex -eq '0x00000040' })
$reportLines.Add('==== bit5/bit6 Focus ====')
$reportLines.Add(('wdata=0x20 events={0} pcs={1}' -f $bit5.Count, (($bit5 | ForEach-Object { $_.PcHex }) -join ',')))
$reportLines.Add(('wdata=0x40 events={0} pcs={1}' -f $bit6.Count, (($bit6 | ForEach-Object { $_.PcHex }) -join ',')))

if ($events.Count -gt 0) {
    $vals = @($events | Where-Object { $_.Wdata -ne $null } | ForEach-Object { [uint32]$_.Wdata })
    if ($vals.Count -gt 0) {
        $uniq = $vals | Sort-Object -Unique
        $reportLines.Add(('all_known_wdata={0}' -f (($uniq | ForEach-Object { To-Hex32 $_ }) -join ',')))

        # Infer physical LED6 bit if sequence is monotonic prefix-ones or single bit walk.
        $prefixSeq = $true
        foreach ($v in $uniq) {
            if (-not (Is-StageLikeProgress $v)) { $prefixSeq = $false; break }
        }
        if ($prefixSeq) {
            $reportLines.Add('inference=sequence resembles progress mask; physical "第6灯" likely maps to bit5 (0x20), while bit6 is 0x40')
        } else {
            $reportLines.Add('inference=non-trivial sequence; physical LED mapping needs board netlist/pin map confirmation')
        }
    }
}

$repDir = Split-Path -Parent $OutReportPath
if ($repDir -and -not (Test-Path $repDir)) { New-Item -ItemType Directory -Force -Path $repDir | Out-Null }
$reportLines | Set-Content -Encoding UTF8 -Path $OutReportPath

Write-Output ("disasm_saved=" + (Resolve-Path $OutDisasmPath).Path)
Write-Output ("report_saved=" + (Resolve-Path $OutReportPath).Path)
Write-Output ("events_found=" + $events.Count)
