param(
    [string]$MemPath = "digital_twin.srcs/sim_iverilog/build/generated/irom.mem"
)

$ErrorActionPreference = 'Stop'

function Get-Bits($v, $hi, $lo) {
    return (($v -shr $lo) -band ((1 -shl ($hi - $lo + 1)) - 1))
}

function Sign-Extend($v, $bits) {
    $sign = 1 -shl ($bits - 1)
    if (($v -band $sign) -ne 0) {
        return ($v -bor (-1 -bxor ((1 -shl $bits) - 1)))
    }
    return $v
}

function Wrap-U32($v) {
    $m = [int64]$v % 4294967296
    if ($m -lt 0) {
        $m += 4294967296
    }
    return [uint32]$m
}

function Decode-Rv32i($pc, $instr) {
    $opcode = Get-Bits $instr 6 0
    $rd = Get-Bits $instr 11 7
    $funct3 = Get-Bits $instr 14 12
    $rs1 = Get-Bits $instr 19 15
    $rs2 = Get-Bits $instr 24 20
    $funct7 = Get-Bits $instr 31 25

    $mn = 'unknown'
    $target = ''

    switch ($opcode) {
        0x63 {
            $imm = ((Get-Bits $instr 31 31) -shl 12) -bor ((Get-Bits $instr 7 7) -shl 11) -bor ((Get-Bits $instr 30 25) -shl 5) -bor ((Get-Bits $instr 11 8) -shl 1)
            $simm = Sign-Extend $imm 13
            $t = Wrap-U32 ([int64]$pc + [int64]$simm)
            $target = ('0x{0:X8}' -f $t)
            switch ($funct3) {
                0 { $mn = "beq x$rs1,x$rs2,$simm" }
                1 { $mn = "bne x$rs1,x$rs2,$simm" }
                4 { $mn = "blt x$rs1,x$rs2,$simm" }
                5 { $mn = "bge x$rs1,x$rs2,$simm" }
                6 { $mn = "bltu x$rs1,x$rs2,$simm" }
                7 { $mn = "bgeu x$rs1,x$rs2,$simm" }
                default { $mn = "branch? f3=$funct3" }
            }
        }
        0x6F {
            $imm = ((Get-Bits $instr 31 31) -shl 20) -bor ((Get-Bits $instr 19 12) -shl 12) -bor ((Get-Bits $instr 20 20) -shl 11) -bor ((Get-Bits $instr 30 21) -shl 1)
            $simm = Sign-Extend $imm 21
            $t = Wrap-U32 ([int64]$pc + [int64]$simm)
            $mn = "jal x$rd,$simm"
            $target = ('0x{0:X8}' -f $t)
        }
        0x67 {
            $imm = Sign-Extend (Get-Bits $instr 31 20) 12
            $mn = "jalr x$rd,x$rs1,$imm"
            $target = "x$rs1+$imm"
        }
        0x73 {
            if ($instr -eq 0x00000073) { $mn = 'ecall' }
            elseif ($instr -eq 0x30200073) { $mn = 'mret' }
            else { $mn = ('system f3={0} csr=0x{1:X3}' -f $funct3, (Get-Bits $instr 31 20)) }
        }
        0x37 { $mn = ('lui x{0},0x{1:X}' -f $rd, (Get-Bits $instr 31 12)) }
        0x17 { $mn = ('auipc x{0},0x{1:X}' -f $rd, (Get-Bits $instr 31 12)) }
        0x03 {
            $imm = Sign-Extend (Get-Bits $instr 31 20) 12
            switch ($funct3) {
                2 { $mn = "lw x$rd,$imm(x$rs1)" }
                0 { $mn = "lb x$rd,$imm(x$rs1)" }
                1 { $mn = "lh x$rd,$imm(x$rs1)" }
                4 { $mn = "lbu x$rd,$imm(x$rs1)" }
                5 { $mn = "lhu x$rd,$imm(x$rs1)" }
                default { $mn = "load? f3=$funct3" }
            }
        }
        0x23 {
            $imm = ((Get-Bits $instr 31 25) -shl 5) -bor (Get-Bits $instr 11 7)
            $imm = Sign-Extend $imm 12
            switch ($funct3) {
                2 { $mn = "sw x$rs2,$imm(x$rs1)" }
                0 { $mn = "sb x$rs2,$imm(x$rs1)" }
                1 { $mn = "sh x$rs2,$imm(x$rs1)" }
                default { $mn = "store? f3=$funct3" }
            }
        }
        0x13 {
            $imm = Sign-Extend (Get-Bits $instr 31 20) 12
            switch ($funct3) {
                0 { $mn = "addi x$rd,x$rs1,$imm" }
                7 { $mn = "andi x$rd,x$rs1,$imm" }
                6 { $mn = "ori x$rd,x$rs1,$imm" }
                4 { $mn = "xori x$rd,x$rs1,$imm" }
                1 { $mn = "slli x$rd,x$rs1,$((Get-Bits $instr 24 20))" }
                5 {
                    if (($funct7 -band 0x20) -ne 0) { $mn = "srai x$rd,x$rs1,$((Get-Bits $instr 24 20))" }
                    else { $mn = "srli x$rd,x$rs1,$((Get-Bits $instr 24 20))" }
                }
                default { $mn = "op-imm? f3=$funct3" }
            }
        }
        0x33 {
            switch ($funct3) {
                0 {
                    if ($funct7 -eq 0x20) { $mn = "sub x$rd,x$rs1,x$rs2" }
                    elseif ($funct7 -eq 0x01) { $mn = "mul x$rd,x$rs1,x$rs2" }
                    else { $mn = "add x$rd,x$rs1,x$rs2" }
                }
                1 { $mn = "sll/mulh x$rd,x$rs1,x$rs2" }
                2 { $mn = "slt x$rd,x$rs1,x$rs2" }
                3 { $mn = "sltu x$rd,x$rs1,x$rs2" }
                4 { $mn = "xor/div x$rd,x$rs1,x$rs2" }
                5 { $mn = "srl/sra x$rd,x$rs1,x$rs2" }
                6 { $mn = "or/rem x$rd,x$rs1,x$rs2" }
                7 { $mn = "and/remu x$rd,x$rs1,x$rs2" }
                default { $mn = "op?" }
            }
        }
        default {
            $mn = ('opcode=0x{0:X2} rd=x{1} rs1=x{2} rs2=x{3} f3={4} f7=0x{5:X2}' -f $opcode, $rd, $rs1, $rs2, $funct3, $funct7)
        }
    }

    [PSCustomObject]@{
        pc = ('0x{0:X8}' -f $pc)
        instr = ('0x{0:X8}' -f $instr)
        decode = $mn
        target = $target
    }
}

$abs = Resolve-Path $MemPath
$words = Get-Content $abs | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[0-9a-fA-F]{1,8}$' } | ForEach-Object { [Convert]::ToUInt32($_,16) }
$base = 0x80000000

$ranges = @(
    @{start=0x80000640; end=0x80000720},
    @{start=0x800007D0; end=0x80000860},
    @{start=0x80000840; end=0x800008C0}
)

foreach($r in $ranges){
    Write-Output ("=== Range 0x{0:X8}..0x{1:X8} ===" -f $r.start, $r.end)
    for($pc=$r.start; $pc -le $r.end; $pc += 4){
        $idx = [int](($pc - $base) / 4)
        if($idx -lt 0 -or $idx -ge $words.Count){
            Write-Output (("PC=0x{0:X8} instr=OUT_OF_RANGE decode=NA target=" -f $pc))
            continue
        }
        $d = Decode-Rv32i $pc $words[$idx]
        Write-Output (("PC={0} instr={1} decode={2} target={3}" -f $d.pc,$d.instr,$d.decode,$d.target))
    }
    Write-Output ""
}
