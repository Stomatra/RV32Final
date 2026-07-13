param (
    [string]$OutCoe = (Join-Path $PSScriptRoot 'irom-uart-hello.coe')
)

$ErrorActionPreference = 'Stop'

$SEG_ADDR         = [uint32][Convert]::ToUInt32('80200020', 16)
$LED_ADDR         = [uint32][Convert]::ToUInt32('80200040', 16)
$UART_TXDATA_ADDR = [uint32][Convert]::ToUInt32('80200060', 16)
$UART_STATUS_ADDR = [uint32][Convert]::ToUInt32('80200064', 16)
$DONE_SEG         = [uint32][Convert]::ToUInt32('12345678', 16)
$script:M12       = [uint64]0xfff
$script:M20       = [uint64]0xfffff

$script:Words = [System.Collections.Generic.List[uint32]]::new()
$script:Labels = @{}
$script:Fixups = [System.Collections.Generic.List[object]]::new()

function To-U32 {
    param ([Parameter(Mandatory = $true)][object]$Value)
    return [uint32](([int64]$Value) -band 0xffffffffL)
}

function Emit {
    param ([Parameter(Mandatory = $true)][uint32]$Word)
    [void]$script:Words.Add($Word)
}

function Mark-Label {
    param ([Parameter(Mandatory = $true)][string]$Name)
    if ($script:Labels.ContainsKey($Name)) {
        throw "Duplicate label: $Name"
    }
    $script:Labels[$Name] = $script:Words.Count
}

function Enc-I {
    param ([int]$Imm, [int]$Rs1, [int]$Funct3, [int]$Rd, [int]$Opcode = 0x13)
    $imm12 = $Imm -band 0xfff
    $word = ($imm12 -shl 20) -bor (($Rs1 -band 0x1f) -shl 15) -bor
            (($Funct3 -band 0x7) -shl 12) -bor (($Rd -band 0x1f) -shl 7) -bor
            ($Opcode -band 0x7f)
    return (To-U32 $word)
}

function Enc-S {
    param ([int]$Imm, [int]$Rs2, [int]$Rs1, [int]$Funct3, [int]$Opcode = 0x23)
    $imm12 = $Imm -band 0xfff
    $word = ((($imm12 -shr 5) -band 0x7f) -shl 25) -bor (($Rs2 -band 0x1f) -shl 20) -bor
            (($Rs1 -band 0x1f) -shl 15) -bor (($Funct3 -band 0x7) -shl 12) -bor
            (($imm12 -band 0x1f) -shl 7) -bor ($Opcode -band 0x7f)
    return (To-U32 $word)
}

function Enc-B {
    param ([int]$Offset, [int]$Rs2, [int]$Rs1, [int]$Funct3, [int]$Opcode = 0x63)
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
    param ([int]$Imm20, [int]$Rd, [int]$Opcode = 0x37)
    $word = (($Imm20 -band 0xfffff) -shl 12) -bor (($Rd -band 0x1f) -shl 7) -bor ($Opcode -band 0x7f)
    return (To-U32 $word)
}

function Enc-J {
    param ([int]$Offset, [int]$Rd, [int]$Opcode = 0x6f)
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
             (($Rd -band 0x1f) -shl 7) -bor ($Opcode -band 0x7f))
    return (To-U32 $word)
}

function Emit-Addi { param ([int]$Rd, [int]$Rs1, [int]$Imm) Emit (Enc-I $Imm $Rs1 0 $Rd 0x13) }
function Emit-Andi { param ([int]$Rd, [int]$Rs1, [int]$Imm) Emit (Enc-I $Imm $Rs1 7 $Rd 0x13) }
function Emit-Lw   { param ([int]$Rd, [int]$Rs1, [int]$Imm) Emit (Enc-I $Imm $Rs1 2 $Rd 0x03) }
function Emit-Sw   { param ([int]$Rs2, [int]$Rs1, [int]$Imm) Emit (Enc-S $Imm $Rs2 $Rs1 2 0x23) }
function Emit-Lui  { param ([int]$Rd, [int]$Imm20) Emit (Enc-U $Imm20 $Rd 0x37) }

function Emit-Li {
    param ([int]$Rd, [uint32]$Value)
    $v = [uint64]$Value
    $lo = [int]($v -band $script:M12)
    if ($lo -ge 0x800) {
        $lo -= 0x1000
    }
    $hi = [int]((($v + [uint64]0x800) -shr 12) -band $script:M20)

    if ($hi -ne 0) {
        Emit-Lui $Rd $hi
        if ($lo -ne 0) {
            Emit-Addi $Rd $Rd $lo
        }
    } else {
        Emit-Addi $Rd 0 $lo
    }
}

function Emit-Beq {
    param ([int]$Rs1, [int]$Rs2, [string]$Label)
    $idx = $script:Words.Count
    Emit ([uint32]0)
    [void]$script:Fixups.Add([pscustomobject]@{
        Kind = 'BEQ'
        Index = $idx
        Label = $Label
        Rs1 = $Rs1
        Rs2 = $Rs2
    })
}

function Emit-Jal {
    param ([string]$Label)
    $idx = $script:Words.Count
    Emit ([uint32]0)
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
            'BEQ' { $script:Words[$fixup.Index] = Enc-B $offset $fixup.Rs2 $fixup.Rs1 0x0 0x63 }
            'JAL' { $script:Words[$fixup.Index] = Enc-J $offset $fixup.Rd 0x6f }
            default { throw "Unknown fixup kind: $($fixup.Kind)" }
        }
    }
}

function Emit-UartPutc {
    param (
        [Parameter(Mandatory = $true)][byte]$Char,
        [Parameter(Mandatory = $true)][uint32]$LedValue,
        [Parameter(Mandatory = $true)][string]$Name
    )

    Emit-Li 10 ([uint32]$Char)     # x10 = char
    Mark-Label "wait_$Name"
    Emit-Lw   11 5 0               # x11 = UART_STATUS
    Emit-Andi 11 11 2              # wait for bit1 = tx_ready
    Emit-Beq  11 0 "wait_$Name"
    Emit-Sw   10 6 0               # UART_TXDATA = char
    Emit-Li   13 $LedValue
    Emit-Sw   13 7 0               # progress LED
}

# x5  = UART_STATUS_ADDR
# x6  = UART_TXDATA_ADDR
# x7  = LED_ADDR
# x8  = SEG_ADDR
Emit-Li 5 $UART_STATUS_ADDR
Emit-Li 6 $UART_TXDATA_ADDR
Emit-Li 7 $LED_ADDR
Emit-Li 8 $SEG_ADDR

Emit-Li 13 ([uint32]1)
Emit-Sw 13 7 0

Emit-UartPutc ([byte][char]'H') ([uint32]2)  'H'
Emit-UartPutc ([byte][char]'i') ([uint32]4)  'i'
Emit-UartPutc ([byte]13)        ([uint32]8)  'cr'
Emit-UartPutc ([byte]10)        ([uint32]16) 'lf'

Emit-Li 13 $DONE_SEG
Emit-Sw 13 8 0

Mark-Label 'done'
Emit-Jal 'done'

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
Write-Host 'Program: LED=1, send H i CR LF, LED=0x10, SEG=0x12345678, loop forever.'
