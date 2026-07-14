from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "digital_twin.srcs" / "sources_1" / "imports" / "test_src" / "irom-z-b-small-test.coe"

LED_ADDR = 0x80200040
SEG_ADDR = 0x80200020

X0 = 0
T0 = 5
T1 = 6
T2 = 7
S4 = 20
S5 = 21
T3 = 28
T4 = 29


class Program:
    def __init__(self):
        self.items = []
        self.labels = {}

    def label(self, name):
        self.labels[name] = len(self.items) * 4

    def emit(self, word):
        self.items.append(("word", word & 0xFFFFFFFF))

    def branch(self, kind, rs1, rs2, label):
        self.items.append(("branch", kind, rs1, rs2, label))

    def jump(self, label):
        self.items.append(("jal", X0, label))

    def resolve(self):
        words = []
        for idx, item in enumerate(self.items):
            pc = idx * 4
            if item[0] == "word":
                words.append(item[1])
            elif item[0] == "branch":
                _, kind, rs1, rs2, label = item
                offset = self.labels[label] - pc
                if kind != "bne":
                    raise ValueError(kind)
                words.append(enc_b(offset, rs1, rs2, 0b001, 0x63))
            elif item[0] == "jal":
                _, rd, label = item
                offset = self.labels[label] - pc
                words.append(enc_j(offset, rd, 0x6F))
            else:
                raise ValueError(item)
        return words


def enc_r(funct7, rs2, rs1, funct3, rd, opcode=0x33):
    return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
        ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def enc_i(imm, rs1, funct3, rd, opcode=0x13):
    imm &= 0xFFF
    return (imm << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
        ((rd & 0x1F) << 7) | (opcode & 0x7F)


def enc_s(imm, rs2, rs1, funct3, opcode=0x23):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
        ((funct3 & 0x7) << 12) | ((imm & 0x1F) << 7) | (opcode & 0x7F)


def enc_b(offset, rs1, rs2, funct3, opcode=0x63):
    if offset % 2:
        raise ValueError(f"unaligned branch offset {offset}")
    imm = offset & 0x1FFF
    return (((imm >> 12) & 0x1) << 31) | (((imm >> 5) & 0x3F) << 25) | \
        ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | \
        (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 0x1) << 7) | (opcode & 0x7F)


def enc_u(imm20, rd, opcode=0x37):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def enc_j(offset, rd, opcode=0x6F):
    if offset % 2:
        raise ValueError(f"unaligned jump offset {offset}")
    imm = offset & 0x1FFFFF
    return (((imm >> 20) & 0x1) << 31) | (((imm >> 1) & 0x3FF) << 21) | \
        (((imm >> 11) & 0x1) << 20) | (((imm >> 12) & 0xFF) << 12) | \
        ((rd & 0x1F) << 7) | (opcode & 0x7F)


def signed12(value):
    value &= 0xFFF
    return value - 0x1000 if value & 0x800 else value


def emit_li(p, rd, value):
    value &= 0xFFFFFFFF
    upper = ((value + 0x800) >> 12) & 0xFFFFF
    lower = signed12(value)
    if upper:
        p.emit(enc_u(upper, rd))
        if lower:
            p.emit(enc_i(lower, rd, 0b000, rd))
    else:
        p.emit(enc_i(lower, X0, 0b000, rd))


def emit_sw_abs(p, rs, addr):
    emit_li(p, T0, addr)
    p.emit(enc_s(0, rs, T0, 0b010))


def z_r(funct7, funct3):
    return enc_r(funct7, T1, T0, funct3, T2)


def z_rori(shamt):
    imm = (0x30 << 5) | (shamt & 0x1F)
    return enc_i(imm, T0, 0b101, T2)


TESTS = [
    ("sh1add", 0, z_r(0x10, 0b010), 0x00000003, 0x00000005, 0x0000000B),
    ("sh2add", 1, z_r(0x10, 0b100), 0x00000003, 0x00000005, 0x00000011),
    ("sh3add", 2, z_r(0x10, 0b110), 0x00000003, 0x00000005, 0x0000001D),
    ("min",    3, z_r(0x05, 0b100), 0xFFFFFFFF, 0x00000001, 0xFFFFFFFF),
    ("minu",   4, z_r(0x05, 0b101), 0xFFFFFFFF, 0x00000001, 0x00000001),
    ("max",    5, z_r(0x05, 0b110), 0xFFFFFFFF, 0x00000001, 0x00000001),
    ("maxu",   6, z_r(0x05, 0b111), 0xFFFFFFFF, 0x00000001, 0xFFFFFFFF),
    ("rol",    7, z_r(0x30, 0b001), 0x80000001, 0x00000001, 0x00000003),
    ("ror",    8, z_r(0x30, 0b101), 0x80000001, 0x00000001, 0xC0000000),
    ("rori",   9, z_rori(1),        0x80000001, None,       0xC0000000),
]


def build():
    p = Program()
    emit_li(p, S4, 0)
    emit_li(p, S5, 0)

    for index, (name, bit, instr, rs1, rs2, expect) in enumerate(TESTS, start=1):
        emit_li(p, T0, rs1)
        if rs2 is not None:
            emit_li(p, T1, rs2)
        p.emit(instr)
        emit_li(p, T3, expect)
        p.branch("bne", T2, T3, f"fail_{index}")
        emit_li(p, T4, 1 << bit)
        p.emit(enc_r(0x00, T4, S4, 0b110, S4))  # or s4, s4, t4
        p.emit(enc_i(1, S5, 0b000, S5))         # addi s5, s5, 1

    emit_sw_abs(p, S4, LED_ADDR)
    emit_sw_abs(p, S5, SEG_ADDR)
    p.label("pass_loop")
    p.jump("pass_loop")

    for index, _test in enumerate(TESTS, start=1):
        p.label(f"fail_{index}")
        emit_sw_abs(p, S4, LED_ADDR)
        emit_li(p, T1, 0xBAD00000 | index)
        emit_sw_abs(p, T1, SEG_ADDR)
        p.label(f"fail_loop_{index}")
        p.jump(f"fail_loop_{index}")

    words = p.resolve()
    if len(words) > 4096:
        raise RuntimeError(f"program too large: {len(words)} words")
    words.extend([0x00000013] * (4096 - len(words)))
    return words


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    words = build()
    with OUT.open("w", newline="\n") as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        for i, word in enumerate(words):
            suffix = ";" if i == len(words) - 1 else ","
            f.write(f"{word:08x}{suffix}\n")
    print(f"Wrote {OUT}")
    print(f"Words: {len(words)}")


if __name__ == "__main__":
    main()
