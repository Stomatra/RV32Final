base = 0x80000000
path = r'D:\digital_twin\digital_twin\digital_twin.srcs\sources_1\imports\test_src\irom.coe'
hexes = []
with open(path) as f:
    for line in f.readlines()[2:]:
        s = line.strip().rstrip(',;')
        if len(s) == 8 and all(c in '0123456789abcdefABCDEF' for c in s):
            hexes.append(int(s, 16))

regs = ['x0','ra','sp','gp','tp','t0','t1','t2','s0','s1','a0','a1','a2','a3','a4','a5','a6','a7','s2','s3','s4','s5','s6','s7','s8','s9','s10','s11','t3','t4','t5','t6']

def sext(v, bits):
    if v >> (bits - 1):
        v -= 1 << bits
    return v

def decode(ins, pc):
    op = ins & 0x7f
    rd = (ins >> 7) & 0x1f
    f3 = (ins >> 12) & 7
    rs1 = (ins >> 15) & 0x1f
    rs2 = (ins >> 20) & 0x1f
    f7 = (ins >> 25) & 0x7f
    txt = 'unknown'
    if op == 0x03:
        imm = sext(ins >> 20, 12)
        names = {0:'lb',1:'lh',2:'lw',4:'lbu',5:'lhu'}
        txt = f"{names.get(f3,'load?')} {regs[rd]}, {imm}({regs[rs1]})"
    elif op == 0x13:
        imm = sext(ins >> 20, 12)
        names = {0:'addi',2:'slti',3:'sltiu',4:'xori',6:'ori',7:'andi'}
        if f3 == 1:
            txt = f"slli {regs[rd]}, {regs[rs1]}, {(ins >> 20) & 0x1f}"
        elif f3 == 5:
            txt = f"{'srai' if f7 == 0x20 else 'srli'} {regs[rd]}, {regs[rs1]}, {(ins >> 20) & 0x1f}"
        else:
            txt = f"{names.get(f3,'opimm?')} {regs[rd]}, {regs[rs1]}, {imm}"
    elif op == 0x17:
        imm = ins & 0xfffff000
        txt = f"auipc {regs[rd]}, 0x{imm >> 12:x}"
    elif op == 0x23:
        imm = sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1f), 12)
        names = {0:'sb',1:'sh',2:'sw'}
        txt = f"{names.get(f3,'store?')} {regs[rs2]}, {imm}({regs[rs1]})"
    elif op == 0x33:
        if f7 == 0x20:
            names = {0:'sub',5:'sra'}
        else:
            names = {0:'add',1:'sll',2:'slt',3:'sltu',4:'xor',5:'srl',6:'or',7:'and'}
        txt = f"{names.get(f3,'op?')} {regs[rd]}, {regs[rs1]}, {regs[rs2]}"
    elif op == 0x37:
        imm = ins & 0xfffff000
        txt = f"lui {regs[rd]}, 0x{imm >> 12:x}"
    elif op == 0x63:
        imm = (((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3f) << 5) | (((ins >> 8) & 0xf) << 1)
        imm = sext(imm, 13)
        names = {0:'beq',1:'bne',4:'blt',5:'bge',6:'bltu',7:'bgeu'}
        txt = f"{names.get(f3,'br?')} {regs[rs1]}, {regs[rs2]}, 0x{(pc + imm) & 0xffffffff:08x}"
    elif op == 0x67:
        imm = sext(ins >> 20, 12)
        txt = f"jalr {regs[rd]}, {imm}({regs[rs1]})"
    elif op == 0x6f:
        imm = (((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xff) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3ff) << 1)
        imm = sext(imm, 21)
        txt = f"jal {regs[rd]}, 0x{(pc + imm) & 0xffffffff:08x}"
    return txt

for start_addr, end_addr, title in [
    (0x80001f80, 0x80001fe4, 'hot callee around 0x80001fa8'),
    (0x80000440, 0x80000510, 'loop block around 0x800004xx'),
    (0x800006a4, 0x80000760, 'loop block around 0x800006xx'),
]:
    print('\n===', title, '===')
    start = (start_addr - base) // 4
    end = (end_addr - base) // 4
    for i in range(start, end + 1):
        pc = base + 4 * i
        ins = hexes[i]
        print(f'0x{pc:08x}: {ins:08x}  {decode(ins, pc)}')
