from pathlib import Path


OUT = Path("digital_twin.srcs/sources_1/imports/test_src/irom-uart-monitor-lite.coe")


REG = {
    "zero": 0,
    "ra": 1,
    "t0": 5,
    "t1": 6,
    "t2": 7,
    "s0": 8,
    "s1": 9,
    "a0": 10,
    "a1": 11,
    "a2": 12,
    "s2": 18,
    "s3": 19,
    "s4": 20,
    "s5": 21,
    "s6": 22,
    "s7": 23,
    "t3": 28,
    "t4": 29,
    "t5": 30,
    "t6": 31,
}


def check_signed(value, bits):
    lo = -(1 << (bits - 1))
    hi = (1 << (bits - 1)) - 1
    if value < lo or value > hi:
        raise ValueError(f"immediate {value} does not fit signed {bits}")
    return value & ((1 << bits) - 1)


def r_type(funct7, rs2, rs1, funct3, rd, opcode):
    return (
        ((funct7 & 0x7F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def i_type(imm, rs1, funct3, rd, opcode):
    imm12 = check_signed(imm, 12)
    return (
        (imm12 << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def shift_i_type(funct7, shamt, rs1, funct3, rd, opcode=0x13):
    return (
        ((funct7 & 0x7F) << 25)
        | ((shamt & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def s_type(imm, rs2, rs1, funct3, opcode):
    imm12 = check_signed(imm, 12)
    return (
        (((imm12 >> 5) & 0x7F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | ((imm12 & 0x1F) << 7)
        | (opcode & 0x7F)
    )


def b_type(offset, rs2, rs1, funct3, opcode):
    if offset % 2:
        raise ValueError(f"branch offset {offset} is not 2-byte aligned")
    imm = check_signed(offset, 13)
    return (
        (((imm >> 12) & 0x1) << 31)
        | (((imm >> 5) & 0x3F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((funct3 & 0x7) << 12)
        | (((imm >> 1) & 0xF) << 8)
        | (((imm >> 11) & 0x1) << 7)
        | (opcode & 0x7F)
    )


def u_type(imm20, rd, opcode):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)


def j_type(offset, rd, opcode):
    if offset % 2:
        raise ValueError(f"jump offset {offset} is not 2-byte aligned")
    imm = check_signed(offset, 21)
    return (
        (((imm >> 20) & 0x1) << 31)
        | (((imm >> 1) & 0x3FF) << 21)
        | (((imm >> 11) & 0x1) << 20)
        | (((imm >> 12) & 0xFF) << 12)
        | ((rd & 0x1F) << 7)
        | (opcode & 0x7F)
    )


class Program:
    def __init__(self):
        self.items = []
        self.labels = {}
        self.unique_id = 0

    def label(self, name):
        self.labels[name] = len(self.items) * 4

    def emit(self, op, *args):
        self.items.append((op, args))

    def unique(self, stem):
        self.unique_id += 1
        return f"{stem}_{self.unique_id}"

    def resolve(self):
        words = []
        for pc, (op, args) in enumerate(self.items):
            addr = pc * 4
            if op == "add":
                rd, rs1, rs2 = args
                word = r_type(0x00, rs2, rs1, 0x0, rd, 0x33)
            elif op == "lui":
                rd, imm20 = args
                word = u_type(imm20, rd, 0x37)
            elif op == "addi":
                rd, rs1, imm = args
                word = i_type(imm, rs1, 0x0, rd, 0x13)
            elif op == "andi":
                rd, rs1, imm = args
                word = i_type(imm, rs1, 0x7, rd, 0x13)
            elif op == "sltiu":
                rd, rs1, imm = args
                word = i_type(imm, rs1, 0x3, rd, 0x13)
            elif op == "srli":
                rd, rs1, shamt = args
                word = shift_i_type(0x00, shamt, rs1, 0x5, rd)
            elif op == "lw":
                rd, imm, rs1 = args
                word = i_type(imm, rs1, 0x2, rd, 0x03)
            elif op == "sw":
                rs2, imm, rs1 = args
                word = s_type(imm, rs2, rs1, 0x2, 0x23)
            elif op == "beq":
                rs1, rs2, label = args
                word = b_type(self.labels[label] - addr, rs2, rs1, 0x0, 0x63)
            elif op == "bne":
                rs1, rs2, label = args
                word = b_type(self.labels[label] - addr, rs2, rs1, 0x1, 0x63)
            elif op == "jal":
                rd, label = args
                word = j_type(self.labels[label] - addr, rd, 0x6F)
            elif op == "jalr":
                rd, rs1, imm = args
                word = i_type(imm, rs1, 0x0, rd, 0x67)
            else:
                raise ValueError(op)
            words.append(word)
        return words


def emit_li(p, rd, value):
    value &= 0xFFFFFFFF
    if value <= 0x7FF:
        p.emit("addi", rd, REG["zero"], value)
        return
    if value >= 0xFFFFF800:
        p.emit("addi", rd, REG["zero"], value - 0x100000000)
        return
    upper = (value + 0x800) >> 12
    lower = value - (upper << 12)
    if lower >= 0x800:
        lower -= 0x1000
    p.emit("lui", rd, upper)
    if lower != 0:
        p.emit("addi", rd, rd, lower)


def emit_putc_const(p, ch):
    emit_li(p, REG["a0"], ch)
    p.emit("jal", REG["t6"], "putc")


def emit_print(p, text):
    for ch in text:
        emit_putc_const(p, ord(ch))


def emit_print_crlf_prompt(p):
    p.emit("jal", REG["ra"], "print_prompt")


def emit_command_dispatch(p):
    x = REG
    commands = [
        ("?", "disp_help"),
        ("s", "disp_status"),
        ("l", "disp_led"),
        ("g", "disp_seg"),
        ("r", "disp_ram"),
        ("c", "disp_clear"),
        ("t", "disp_timer"),
        ("\r", "disp_ignore"),
        ("\n", "disp_ignore"),
    ]
    for ch, label in commands:
        emit_li(p, x["t1"], ord(ch))
        p.emit("beq", x["a0"], x["t1"], label)
    p.emit("jal", x["zero"], "cmd_unknown")
    for _, label in commands:
        p.label(label)
        target = {
            "disp_help": "cmd_help",
            "disp_status": "cmd_status",
            "disp_led": "cmd_led",
            "disp_seg": "cmd_seg",
            "disp_ram": "cmd_ram",
            "disp_clear": "cmd_clear",
            "disp_timer": "cmd_timer",
            "disp_ignore": "monitor_loop",
        }[label]
        p.emit("jal", x["zero"], target)


def emit_led_patterns(p):
    x = REG
    cases = [
        (0, 0x00000001, 1),
        (1, 0x00000010, 2),
        (2, 0x03030303, 3),
        (3, 0x078B7323, 4),
    ]
    for idx, _, _ in cases:
        emit_li(p, x["t1"], idx)
        p.emit("beq", x["s4"], x["t1"], f"cmd_led_case_{idx}")
    emit_li(p, x["s2"], 0x00000000)
    emit_li(p, x["s4"], 0)
    p.emit("jal", x["zero"], "cmd_led_write")
    for idx, value, next_idx in cases:
        p.label(f"cmd_led_case_{idx}")
        emit_li(p, x["s2"], value)
        emit_li(p, x["s4"], next_idx)
        p.emit("jal", x["zero"], "cmd_led_write")


def emit_seg_patterns(p):
    x = REG
    cases = [
        (0, 0x12345678, 1),
        (1, 0x20260713, 2),
        (2, 0xDEADBEEF, 3),
    ]
    for idx, _, _ in cases:
        emit_li(p, x["t1"], idx)
        p.emit("beq", x["s5"], x["t1"], f"cmd_seg_case_{idx}")
    emit_li(p, x["s3"], 0x00000000)
    emit_li(p, x["s5"], 0)
    p.emit("jal", x["zero"], "cmd_seg_write")
    for idx, value, next_idx in cases:
        p.label(f"cmd_seg_case_{idx}")
        emit_li(p, x["s3"], value)
        emit_li(p, x["s5"], next_idx)
        p.emit("jal", x["zero"], "cmd_seg_write")


def emit_ram_test(p):
    x = REG
    values = [0xA5000000 + i * 0x00010101 for i in range(16)]
    for i, value in enumerate(values):
        emit_li(p, x["t1"], value)
        p.emit("sw", x["t1"], i * 4, x["s1"])
    for i, value in enumerate(values):
        emit_li(p, x["t1"], value)
        p.emit("lw", x["t2"], i * 4, x["s1"])
        p.emit("bne", x["t2"], x["t1"], "cmd_ram_fail")


def emit_print_hex32(p):
    x = REG
    p.label("print_hex32")
    p.emit("addi", x["a1"], x["a0"], 0)
    for shift in [28, 24, 20, 16, 12, 8, 4, 0]:
        letter = p.unique(f"hex_letter_{shift}")
        done = p.unique(f"hex_done_{shift}")
        if shift:
            p.emit("srli", x["t1"], x["a1"], shift)
            p.emit("andi", x["t1"], x["t1"], 0xF)
        else:
            p.emit("andi", x["t1"], x["a1"], 0xF)
        p.emit("sltiu", x["t2"], x["t1"], 10)
        p.emit("beq", x["t2"], x["zero"], letter)
        p.emit("addi", x["a0"], x["t1"], 48)
        p.emit("jal", x["t6"], "putc")
        p.emit("jal", x["zero"], done)
        p.label(letter)
        p.emit("addi", x["a0"], x["t1"], 55)
        p.emit("jal", x["t6"], "putc")
        p.label(done)
    p.emit("jalr", x["zero"], x["ra"], 0)


def build_program():
    x = REG
    p = Program()

    p.emit("lui", x["s0"], 0x80200)          # MMIO base
    p.emit("lui", x["s1"], 0x80100)          # DRAM base
    emit_li(p, x["s2"], 0x00000001)          # LED shadow
    emit_li(p, x["s3"], 0x00000000)          # SEG shadow
    emit_li(p, x["s4"], 1)                   # LED pattern index
    emit_li(p, x["s5"], 0)                   # SEG pattern index
    p.emit("sw", x["s2"], 0x40, x["s0"])
    p.emit("sw", x["s3"], 0x20, x["s0"])

    emit_print(p, "RV32 UART MONITOR\r\n? help")
    emit_print_crlf_prompt(p)

    p.label("monitor_loop")
    p.label("wait_cmd")
    p.emit("lw", x["t1"], 0x64, x["s0"])
    p.emit("andi", x["t1"], x["t1"], 4)
    p.emit("beq", x["t1"], x["zero"], "wait_cmd")
    p.emit("lw", x["a0"], 0x68, x["s0"])
    p.emit("andi", x["a0"], x["a0"], 0x0FF)
    emit_command_dispatch(p)

    p.label("cmd_help")
    emit_print(
        p,
        "\r\nCommands:\r\n"
        "? help\r\n"
        "s status\r\n"
        "l led pattern\r\n"
        "g seg pattern\r\n"
        "r ram test\r\n"
        "c clear uart\r\n"
        "t timer",
    )
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_status")
    emit_print(p, "\r\nLED=0x")
    p.emit("addi", x["a0"], x["s2"], 0)
    p.emit("jal", x["ra"], "print_hex32")
    emit_print(p, "\r\nSEG=0x")
    p.emit("addi", x["a0"], x["s3"], 0)
    p.emit("jal", x["ra"], "print_hex32")
    emit_print(p, "\r\nRXOVR=")
    p.emit("lw", x["t1"], 0x64, x["s0"])
    p.emit("andi", x["t1"], x["t1"], 8)
    p.emit("beq", x["t1"], x["zero"], "cmd_status_rxovr_zero")
    emit_putc_const(p, ord("1"))
    p.emit("jal", x["zero"], "cmd_status_done")
    p.label("cmd_status_rxovr_zero")
    emit_putc_const(p, ord("0"))
    p.label("cmd_status_done")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_led")
    emit_led_patterns(p)
    p.label("cmd_led_write")
    p.emit("sw", x["s2"], 0x40, x["s0"])
    emit_print(p, "\r\nLED OK")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_seg")
    emit_seg_patterns(p)
    p.label("cmd_seg_write")
    p.emit("sw", x["s3"], 0x20, x["s0"])
    emit_print(p, "\r\nSEG OK")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_ram")
    emit_ram_test(p)
    emit_print(p, "\r\nRAM PASS")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")
    p.label("cmd_ram_fail")
    emit_li(p, x["s3"], 0xBAD00001)
    p.emit("sw", x["s3"], 0x20, x["s0"])
    emit_print(p, "\r\nRAM FAIL")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_clear")
    emit_li(p, x["t1"], 2)
    p.emit("sw", x["t1"], 0x6C, x["s0"])
    emit_print(p, "\r\nCLR OK")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_timer")
    emit_print(p, "\r\nCNT=0x")
    p.emit("lw", x["a0"], 0x50, x["s0"])
    p.emit("jal", x["ra"], "print_hex32")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_unknown")
    emit_print(p, "\r\nERR")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("print_prompt")
    emit_print(p, "\r\n> ")
    p.emit("jalr", x["zero"], x["ra"], 0)

    emit_print_hex32(p)

    p.label("putc")
    p.emit("lw", x["t1"], 0x64, x["s0"])
    p.emit("andi", x["t1"], x["t1"], 2)
    p.emit("beq", x["t1"], x["zero"], "putc")
    p.emit("sw", x["a0"], 0x60, x["s0"])
    p.emit("jalr", x["zero"], x["t6"], 0)

    return p.resolve()


def write_coe(words):
    OUT.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "memory_initialization_radix=16;",
        "memory_initialization_vector=",
    ]
    for idx, word in enumerate(words):
        tail = ";" if idx == len(words) - 1 else ","
        lines.append(f"{word:08X}{tail}")
    OUT.write_text("\n".join(lines) + "\n", encoding="ascii")


if __name__ == "__main__":
    program_words = build_program()
    write_coe(program_words)
    print(f"Wrote {OUT} ({len(program_words)} words)")
    print("FIRST8=" + ",".join(f"{word:08X}" for word in program_words[:8]))
