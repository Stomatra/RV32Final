param (
    [string]$OutCoe = (Join-Path $PSScriptRoot 'irom-z-light.coe')
)

$ErrorActionPreference = 'Stop'

$SEG_ADDR = [uint32][Convert]::ToUInt32('80200020', 16)
$LED_ADDR = [uint32][Convert]::ToUInt32('80200040', 16)
$CNT_ADDR = [uint32][Convert]::ToUInt32('80200050', 16)
$CNT_START = [uint32][Convert]::ToUInt32('80000000', 16)
$CNT_STOP = [uint32][Convert]::ToUInt32('ffffffff', 16)
$PASS_LED = [uint32][Convert]::ToUInt32('90606092', 16)
$PASS_SEG = [uint32][Convert]::ToUInt32('37000015', 16)
$FAIL_BASE = [uint32][Convert]::ToUInt32('bad00000', 16)
$script:U1 = [uint64]1
$script:M8 = [uint64]0xff
$script:M12 = [uint64]0xfff
$script:M16 = [uint64]0xffff
$script:M20 = [uint64]0xfffff
$script:M32 = [uint64][Convert]::ToUInt64('ffffffff', 16)
$script:SEXT_B_MASK = [uint64][Convert]::ToUInt64('ffffff00', 16)
$script:SEXT_H_MASK = [uint64][Convert]::ToUInt64('ffff0000', 16)

$script:Words = [System.Collections.Generic.List[uint32]]::new()
$script:Comments = [System.Collections.Generic.List[string]]::new()
$script:Labels = @{}
$script:Fixups = [System.Collections.Generic.List[object]]::new()

function Hex32 {
    param ([Parameter(Mandatory = $true)][string]$Hex)
    return [uint32][Convert]::ToUInt32(($Hex -replace '_', ''), 16)
}

function To-U32 {
    param ([Parameter(Mandatory = $true)][object]$Value)
    return [uint32](([int64]$Value) -band 0xffffffffL)
}

function Format-U32Hex {
    param ([Parameter(Mandatory = $true)][uint32]$Value)
    return ('0x{0:x8}' -f $Value)
}

function Emit {
    param (
        [Parameter(Mandatory = $true)][uint32]$Word,
        [string]$Comment = ''
    )
    [void]$script:Words.Add($Word)
    [void]$script:Comments.Add($Comment)
}

function Mark-Label {
    param ([Parameter(Mandatory = $true)][string]$Name)
    if ($script:Labels.ContainsKey($Name)) {
        throw "Duplicate label: $Name"
    }
    $script:Labels[$Name] = $script:Words.Count
}

function Enc-R {
    param (
        [int]$Funct7,
        [int]$Rs2,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Rd,
        [int]$Opcode = 0x33
    )
    $word = (($Funct7 -band 0x7f) -shl 25) -bor (($Rs2 -band 0x1f) -shl 20) -bor
            (($Rs1 -band 0x1f) -shl 15) -bor (($Funct3 -band 0x7) -shl 12) -bor
            (($Rd -band 0x1f) -shl 7) -bor ($Opcode -band 0x7f)
    return (To-U32 $word)
}

function Enc-I {
    param (
        [int]$Imm,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Rd,
        [int]$Opcode = 0x13
    )
    $imm12 = $Imm -band 0xfff
    $word = ($imm12 -shl 20) -bor (($Rs1 -band 0x1f) -shl 15) -bor
            (($Funct3 -band 0x7) -shl 12) -bor (($Rd -band 0x1f) -shl 7) -bor
            ($Opcode -band 0x7f)
    return (To-U32 $word)
}

function Enc-S {
    param (
        [int]$Imm,
        [int]$Rs2,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Opcode = 0x23
    )
    $imm12 = $Imm -band 0xfff
    $word = ((($imm12 -shr 5) -band 0x7f) -shl 25) -bor (($Rs2 -band 0x1f) -shl 20) -bor
            (($Rs1 -band 0x1f) -shl 15) -bor (($Funct3 -band 0x7) -shl 12) -bor
            (($imm12 -band 0x1f) -shl 7) -bor ($Opcode -band 0x7f)
    return (To-U32 $word)
}

function Enc-B {
    param (
        [int]$Offset,
        [int]$Rs2,
        [int]$Rs1,
        [int]$Funct3,
        [int]$Opcode = 0x63
    )
    if (($Offset % 2) -ne 0) {
        throw "Branch offset must be 2-byte aligned: $Offset"
    }
    if (($Offset -lt -4096) -or ($Offset -gt 4094)) {
        throw "Branch offset out of range: $Offset"
    }
    $imm = $Offset -band 0x1fff
    $word = (((($imm -shr 12) -band 0x1) -shl 31) -bor
             ((($imm -shr 5) -band 0x3f) -shl 25) -bor
             (($Rs2 -band 0x1f) -shl 20) -bor
             (($Rs1 -band 0x1f) -shl 15) -bor
             (($Funct3 -band 0x7) -shl 12) -bor
             ((($imm -shr 1) -band 0xf) -shl 8) -bor
             ((($imm -shr 11) -band 0x1) -shl 7) -bor
             ($Opcode -band 0x7f))
    return (To-U32 $word)
}

function Enc-U {
    param (
        [int]$Imm20,
        [int]$Rd,
        [int]$Opcode = 0x37
    )
    $word = (($Imm20 -band 0xfffff) -shl 12) -bor (($Rd -band 0x1f) -shl 7) -bor ($Opcode -band 0x7f)
    return (To-U32 $word)
}

function Enc-J {
    param (
        [int]$Offset,
        [int]$Rd,
        [int]$Opcode = 0x6f
    )
    if (($Offset % 2) -ne 0) {
        throw "JAL offset must be 2-byte aligned: $Offset"
    }
    if (($Offset -lt -1048576) -or ($Offset -gt 1048574)) {
        throw "JAL offset out of range: $Offset"
    }
    $imm = $Offset -band 0x1fffff
    $word = (((($imm -shr 20) -band 0x1) -shl 31) -bor
             ((($imm -shr 1) -band 0x3ff) -shl 21) -bor
             ((($imm -shr 11) -band 0x1) -shl 20) -bor
             ((($imm -shr 12) -band 0xff) -shl 12) -bor
             (($Rd -band 0x1f) -shl 7) -bor
             ($Opcode -band 0x7f))
    return (To-U32 $word)
}

function Emit-Addi {
    param ([int]$Rd, [int]$Rs1, [int]$Imm, [string]$Comment = '')
    Emit (Enc-I $Imm $Rs1 0 $Rd 0x13) $Comment
}

function Emit-Lui {
    param ([int]$Rd, [int]$Imm20, [string]$Comment = '')
    Emit (Enc-U $Imm20 $Rd 0x37) $Comment
}

function Emit-Li {
    param ([int]$Rd, [uint32]$Value, [string]$Comment = '')

    $v = [uint64]$Value
    $lo = [int]($v -band $script:M12)
    if ($lo -ge 0x800) {
        $lo -= 0x1000
    }
    $hi = [int]((($v + [uint64]0x800) -shr 12) -band $script:M20)

    if ($hi -ne 0) {
        Emit-Lui $Rd $hi $Comment
        if ($lo -ne 0) {
            Emit-Addi $Rd $Rd $lo
        }
    } else {
        Emit-Addi $Rd 0 $lo $Comment
    }
}

function Emit-Nop {
    Emit-Addi 0 0 0 'nop'
}

function Emit-Or {
    param ([int]$Rd, [int]$Rs1, [int]$Rs2, [string]$Comment = '')
    Emit (Enc-R 0x00 $Rs2 $Rs1 0x6 $Rd 0x33) $Comment
}

function Emit-Sw {
    param ([int]$Rs2, [int]$Rs1, [int]$Imm, [string]$Comment = '')
    Emit (Enc-S $Imm $Rs2 $Rs1 0x2 0x23) $Comment
}

function Emit-SwAbs {
    param ([int]$Rs, [uint32]$Addr, [string]$Comment = '')
    Emit-Li 28 $Addr "addr $(Format-U32Hex $Addr)"
    Emit-Nop
    Emit-Nop
    Emit-Sw $Rs 28 0 $Comment
}

function Emit-Bne {
    param ([int]$Rs1, [int]$Rs2, [string]$Label, [string]$Comment = '')
    $idx = $script:Words.Count
    Emit ([uint32]0) $Comment
    [void]$script:Fixups.Add([pscustomobject]@{
        Kind = 'BNE'
        Index = $idx
        Label = $Label
        Rs1 = $Rs1
        Rs2 = $Rs2
    })
}

function Emit-Jal {
    param ([string]$Label, [string]$Comment = '')
    $idx = $script:Words.Count
    Emit ([uint32]0) $Comment
    [void]$script:Fixups.Add([pscustomobject]@{
        Kind = 'JAL'
        Index = $idx
        Label = $Label
        Rd = 0
    })
}

function Patch-Fixups {
    foreach ($fixup in $script:Fixups) {
        if (-not $script:Labels.ContainsKey($fixup.Label)) {
            throw "Missing label: $($fixup.Label)"
        }
        $offset = [int](($script:Labels[$fixup.Label] - $fixup.Index) * 4)
        switch ($fixup.Kind) {
            'BNE' { $script:Words[$fixup.Index] = Enc-B $offset $fixup.Rs2 $fixup.Rs1 0x1 0x63 }
            'JAL' { $script:Words[$fixup.Index] = Enc-J $offset $fixup.Rd 0x6f }
            default { throw "Unknown fixup kind: $($fixup.Kind)" }
        }
    }
}

function Bit {
    param ([uint32]$Value, [int]$Index)
    return ([uint64]$Value -shr $Index) -band $script:U1
}

function Mask-Bit {
    param ([int]$Index)
    return [uint32](($script:U1 -shl ($Index -band 31)) -band $script:M32)
}

function Ref-Andn { param ([uint32]$A, [uint32]$B) return [uint32](([uint64]$A) -band (([uint64]$B) -bxor $script:M32)) }
function Ref-Orn  { param ([uint32]$A, [uint32]$B) return [uint32](([uint64]$A) -bor  (([uint64]$B) -bxor $script:M32)) }
function Ref-Xnor { param ([uint32]$A, [uint32]$B) return [uint32](((([uint64]$A) -bxor ([uint64]$B)) -bxor $script:M32) -band $script:M32) }

function Ref-SextB {
    param ([uint32]$A)
    $b = [uint32]($A -band 0xff)
    if (($b -band 0x80) -ne 0) { return [uint32](([uint64]$b) -bor $script:SEXT_B_MASK) }
    return $b
}

function Ref-SextH {
    param ([uint32]$A)
    $h = [uint32]($A -band 0xffff)
    if (($h -band 0x8000) -ne 0) { return [uint32](([uint64]$h) -bor $script:SEXT_H_MASK) }
    return $h
}

function Ref-ZextH { param ([uint32]$A) return [uint32]($A -band 0xffff) }

function Ref-OrcB {
    param ([uint32]$A)
    $out = [uint64]0
    for ($i = 0; $i -lt 4; $i++) {
        $byte = ([uint64]$A -shr ($i * 8)) -band $script:M8
        if ($byte -ne 0) {
            $out = $out -bor ($script:M8 -shl ($i * 8))
        }
    }
    return [uint32]$out
}

function Ref-Pack  { param ([uint32]$A, [uint32]$B) return [uint32]((([uint64]$B -band $script:M16) -shl 16) -bor ([uint64]$A -band $script:M16)) }
function Ref-PackH { param ([uint32]$A, [uint32]$B) return [uint32]((([uint64]$B -band $script:M8) -shl 8) -bor ([uint64]$A -band $script:M8)) }
function Ref-Rev8  { param ([uint32]$A) return [uint32](((([uint64]$A) -band $script:M8) -shl 24) -bor ((([uint64]$A -shr 8) -band $script:M8) -shl 16) -bor ((([uint64]$A -shr 16) -band $script:M8) -shl 8) -bor ((([uint64]$A -shr 24) -band $script:M8))) }

function Reverse-Byte {
    param ([uint32]$Byte)
    $out = [uint64]0
    for ($i = 0; $i -lt 8; $i++) {
        $out = $out -bor ((([uint64]$Byte -shr $i) -band $script:U1) -shl (7 - $i))
    }
    return [uint32]$out
}

function Ref-Brev8 {
    param ([uint32]$A)
    $out = [uint64]0
    for ($i = 0; $i -lt 4; $i++) {
        $rb = Reverse-Byte ([uint32](([uint64]$A -shr ($i * 8)) -band $script:M8))
        $out = $out -bor ([uint64]$rb -shl ($i * 8))
    }
    return [uint32]$out
}

function Ref-FromBitList {
    param ([uint32]$A, [int[]]$List)
    $out = [uint64]0
    for ($i = 0; $i -lt 32; $i++) {
        $out = $out -bor ((Bit $A $List[$i]) -shl (31 - $i))
    }
    return [uint32]$out
}

function Ref-Zip {
    param ([uint32]$A)
    return Ref-FromBitList $A @(31,15,30,14,29,13,28,12,27,11,26,10,25,9,24,8,23,7,22,6,21,5,20,4,19,3,18,2,17,1,16,0)
}

function Ref-Unzip {
    param ([uint32]$A)
    return Ref-FromBitList $A @(31,29,27,25,23,21,19,17,15,13,11,9,7,5,3,1,30,28,26,24,22,20,18,16,14,12,10,8,6,4,2,0)
}

function Ref-Bclr { param ([uint32]$A, [uint32]$B) return [uint32](([uint64]$A) -band (([uint64](Mask-Bit ([int]($B -band 31)))) -bxor $script:M32)) }
function Ref-Bext { param ([uint32]$A, [uint32]$B) return [uint32]((([uint64]$A) -shr ([int]($B -band 31))) -band $script:U1) }
function Ref-Binv { param ([uint32]$A, [uint32]$B) return [uint32](([uint64]$A) -bxor ([uint64](Mask-Bit ([int]($B -band 31))))) }
function Ref-Bset { param ([uint32]$A, [uint32]$B) return [uint32](([uint64]$A) -bor  ([uint64](Mask-Bit ([int]($B -band 31))))) }

function Z-R {
    param ([int]$Funct7, [int]$Rs2, [int]$Rs1, [int]$Funct3, [int]$Rd)
    return Enc-R $Funct7 $Rs2 $Rs1 $Funct3 $Rd 0x33
}

function Z-I {
    param ([int]$Imm12, [int]$Rs1, [int]$Funct3, [int]$Rd)
    return Enc-I $Imm12 $Rs1 $Funct3 $Rd 0x13
}

$rs1Common = Hex32 '123480f0'
$rs2Common = Hex32 '0f0f00aa'

$tests = @(
    [pscustomobject]@{ Index = 1;  Name = 'andn';   Rs1 = $rs1Common;       Rs2 = $rs2Common;       Word = (Z-R 0x20 2 1 0x7 3); Expected = (Ref-Andn $rs1Common $rs2Common);       Note = 'rs1 & ~rs2' },
    [pscustomobject]@{ Index = 2;  Name = 'orn';    Rs1 = $rs1Common;       Rs2 = $rs2Common;       Word = (Z-R 0x20 2 1 0x6 3); Expected = (Ref-Orn  $rs1Common $rs2Common);       Note = 'rs1 | ~rs2' },
    [pscustomobject]@{ Index = 3;  Name = 'xnor';   Rs1 = $rs1Common;       Rs2 = $rs2Common;       Word = (Z-R 0x20 2 1 0x4 3); Expected = (Ref-Xnor $rs1Common $rs2Common);       Note = '~(rs1 ^ rs2)' },
    [pscustomobject]@{ Index = 4;  Name = 'sext.b'; Rs1 = (Hex32 '000000f0');   Rs2 = 0;               Word = (Z-I 0x604 1 0x1 3);  Expected = (Ref-SextB (Hex32 '000000f0'));             Note = 'sign extend low byte' },
    [pscustomobject]@{ Index = 5;  Name = 'sext.h'; Rs1 = (Hex32 '000080f0');   Rs2 = 0;               Word = (Z-I 0x605 1 0x1 3);  Expected = (Ref-SextH (Hex32 '000080f0'));             Note = 'sign extend low halfword' },
    [pscustomobject]@{ Index = 6;  Name = 'zext.h'; Rs1 = $rs1Common;       Rs2 = 0;               Word = (Z-R 0x04 0 1 0x4 3); Expected = (Ref-ZextH $rs1Common);                 Note = 'zero extend low halfword; rs2=x0 encoding' },
    [pscustomobject]@{ Index = 7;  Name = 'orc.b';  Rs1 = (Hex32 '12008000');   Rs2 = 0;               Word = (Z-I 0x287 1 0x5 3);  Expected = (Ref-OrcB (Hex32 '12008000'));              Note = 'nonzero byte -> ff, zero byte -> 00' },
    [pscustomobject]@{ Index = 8;  Name = 'pack';   Rs1 = $rs1Common;       Rs2 = $rs2Common;       Word = (Z-R 0x04 2 1 0x4 3); Expected = (Ref-Pack $rs1Common $rs2Common);       Note = '{rs2[15:0], rs1[15:0]}' },
    [pscustomobject]@{ Index = 9;  Name = 'packh';  Rs1 = $rs1Common;       Rs2 = $rs2Common;       Word = (Z-R 0x04 2 1 0x7 3); Expected = (Ref-PackH $rs1Common $rs2Common);      Note = '{16''h0, rs2[7:0], rs1[7:0]}' },
    [pscustomobject]@{ Index = 10; Name = 'rev8';   Rs1 = $rs1Common;       Rs2 = 0;               Word = (Z-I 0x698 1 0x5 3);  Expected = (Ref-Rev8 $rs1Common);                  Note = 'byte reverse' },
    [pscustomobject]@{ Index = 11; Name = 'brev8';  Rs1 = $rs1Common;       Rs2 = 0;               Word = (Z-I 0x687 1 0x5 3);  Expected = (Ref-Brev8 $rs1Common);                 Note = 'reverse bits inside each byte' },
    [pscustomobject]@{ Index = 12; Name = 'zip';    Rs1 = (Hex32 '0000ffff');   Rs2 = 0;               Word = (Z-I ((0x04 -shl 5) -bor 15) 1 0x1 3); Expected = (Ref-Zip (Hex32 '0000ffff'));   Note = 'bit interleave' },
    [pscustomobject]@{ Index = 13; Name = 'unzip';  Rs1 = (Hex32 '55555555');   Rs2 = 0;               Word = (Z-I ((0x04 -shl 5) -bor 15) 1 0x5 3); Expected = (Ref-Unzip (Hex32 '55555555')); Note = 'bit deinterleave' },
    [pscustomobject]@{ Index = 14; Name = 'bclr';   Rs1 = (Hex32 '000000ff');   Rs2 = 3;               Word = (Z-R 0x24 2 1 0x1 3); Expected = (Ref-Bclr (Hex32 '000000ff') 3);             Note = 'clear bit rs2[4:0]' },
    [pscustomobject]@{ Index = 15; Name = 'bclri';  Rs1 = (Hex32 '000000ff');   Rs2 = 3;               Word = (Z-I ((0x24 -shl 5) -bor 3) 1 0x1 3); Expected = (Ref-Bclr (Hex32 '000000ff') 3); Note = 'clear bit imm[4:0]' },
    [pscustomobject]@{ Index = 16; Name = 'bext';   Rs1 = (Hex32 '00000080');   Rs2 = 7;               Word = (Z-R 0x24 2 1 0x5 3); Expected = (Ref-Bext (Hex32 '00000080') 7);             Note = 'extract bit rs2[4:0]' },
    [pscustomobject]@{ Index = 17; Name = 'bexti';  Rs1 = (Hex32 '00000080');   Rs2 = 7;               Word = (Z-I ((0x24 -shl 5) -bor 7) 1 0x5 3); Expected = (Ref-Bext (Hex32 '00000080') 7); Note = 'extract bit imm[4:0]' },
    [pscustomobject]@{ Index = 18; Name = 'binv';   Rs1 = 0;               Rs2 = 4;               Word = (Z-R 0x34 2 1 0x1 3); Expected = (Ref-Binv 0 4);                          Note = 'invert bit rs2[4:0]' },
    [pscustomobject]@{ Index = 19; Name = 'binvi';  Rs1 = 0;               Rs2 = 4;               Word = (Z-I ((0x34 -shl 5) -bor 4) 1 0x1 3); Expected = (Ref-Binv 0 4);             Note = 'invert bit imm[4:0]' },
    [pscustomobject]@{ Index = 20; Name = 'bset';   Rs1 = 0;               Rs2 = 5;               Word = (Z-R 0x14 2 1 0x1 3); Expected = (Ref-Bset 0 5);                          Note = 'set bit rs2[4:0]' },
    [pscustomobject]@{ Index = 21; Name = 'bseti';  Rs1 = 0;               Rs2 = 5;               Word = (Z-I ((0x14 -shl 5) -bor 5) 1 0x1 3); Expected = (Ref-Bset 0 5);             Note = 'set bit imm[4:0]' }
)

function Emit-Test {
    param ([Parameter(Mandatory = $true)]$Test)

    Emit-Li 31 ([uint32]$Test.Index) "test $($Test.Index): $($Test.Name)"
    Emit-Li 1 ([uint32]$Test.Rs1) 'rs1 input'
    Emit-Li 2 ([uint32]$Test.Rs2) 'rs2 input/unused'
    Emit-Nop
    Emit-Nop
    Emit ([uint32]$Test.Word) "$($Test.Name) .word"
    Emit-Li 4 ([uint32]$Test.Expected) "expected $($Test.Name)"
    Emit-Nop
    Emit-Nop
    Emit-Bne 3 4 'fail' "fail if $($Test.Name) mismatches"
}

Emit-Li 29 $CNT_START 'counter start command'
Emit-SwAbs 29 $CNT_ADDR 'CNT start'
Emit-Li 29 ([uint32]0) 'clear pass LED'
Emit-SwAbs 29 $LED_ADDR 'LED clear'
Emit-Li 29 (Hex32 '37000000') 'boot/progress SEG prefix'
Emit-SwAbs 29 $SEG_ADDR 'SEG init'

foreach ($test in $tests) {
    Emit-Test $test
}

Mark-Label 'pass'
Emit-Li 29 $CNT_STOP 'counter stop command'
Emit-SwAbs 29 $CNT_ADDR 'CNT stop'
Emit-Li 29 $PASS_LED 'check-pass pattern plus Z-light pass LED bit'
Emit-SwAbs 29 $LED_ADDR 'LED pass'
Emit-Li 29 $PASS_SEG 'SEG pass'
Emit-SwAbs 29 $SEG_ADDR 'SEG pass'
Mark-Label 'pass_loop'
Emit-Jal 'pass_loop' 'hold pass state'

Mark-Label 'fail'
Emit-Li 29 $CNT_STOP 'counter stop command'
Emit-SwAbs 29 $CNT_ADDR 'CNT stop on fail'
Emit-Li 29 $FAIL_BASE 'fail base'
Emit-Or 29 29 31 'SEG fail = 0xbad00000 | test_index'
Emit-SwAbs 29 $SEG_ADDR 'SEG fail'
Mark-Label 'fail_loop'
Emit-Jal 'fail_loop' 'hold fail state'

Patch-Fixups

$coeLines = [System.Collections.Generic.List[string]]::new()
[void]$coeLines.Add('memory_initialization_radix=16;')
[void]$coeLines.Add('memory_initialization_vector=')
for ($i = 0; $i -lt $script:Words.Count; $i++) {
    $suffix = if ($i -eq ($script:Words.Count - 1)) { ';' } else { ',' }
    [void]$coeLines.Add(('{0:x8}{1}' -f $script:Words[$i], $suffix))
}

$outDir = Split-Path -Parent $OutCoe
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}
Set-Content -Path $OutCoe -Value ($coeLines -join [Environment]::NewLine) -Encoding ascii

Write-Host ("Generated {0} words -> {1}" -f $script:Words.Count, (Resolve-Path $OutCoe).Path)
Write-Host 'Z_LIGHT tests:'
foreach ($test in $tests) {
    Write-Host ('  {0,2}. {1,-7} rs1={2} rs2={3} expect={4} ({5})' -f
        $test.Index,
        $test.Name,
        (Format-U32Hex ([uint32]$test.Rs1)),
        (Format-U32Hex ([uint32]$test.Rs2)),
        (Format-U32Hex ([uint32]$test.Expected)),
        $test.Note)
}
