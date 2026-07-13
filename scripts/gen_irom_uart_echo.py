from pathlib import Path


OUT = Path("digital_twin.srcs/sources_1/imports/test_src/irom-uart-echo.coe")


REG = {
    "zero": 0,
    "ra": 1,
    "t0": 5,
    "t1": 6,
    "t2": 7,
    "s0": 8,
    "a0": 10,
    "a1": 11,
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


def lui(rd, imm20):
    return u_type(imm20, rd, 0x37)


def addi(rd, rs1, imm):
    return i_type(imm, rs1, 0x0, rd, 0x13)


def andi(rd, rs1, imm):
    return i_type(imm, rs1, 0x7, rd, 0x13)


def lw(rd, imm, rs1):
    return i_type(imm, rs1, 0x2, rd, 0x03)


def sw(rs2, imm, rs1):
    return s_type(imm, rs2, rs1, 0x2, 0x23)


def beq(rs1, rs2, offset):
    return b_type(offset, rs2, rs1, 0x0, 0x63)


def jal(rd, offset):
    return j_type(offset, rd, 0x6F)


def jalr(rd, rs1, imm):
    return i_type(imm, rs1, 0x0, rd, 0x67)


class Program:
    def __init__(self):
        self.items = []
        self.labels = {}

    def label(self, name):
        self.labels[name] = len(self.items) * 4

    def emit(self, op, *args):
        self.items.append((op, args))

    def resolve(self):
        words = []
        for pc, (op, args) in enumerate(self.items):
            addr = pc * 4
            if op == "lui":
                rd, imm20 = args
                word = lui(rd, imm20)
            elif op == "addi":
                rd, rs1, imm = args
                word = addi(rd, rs1, imm)
            elif op == "andi":
                rd, rs1, imm = args
                word = andi(rd, rs1, imm)
            elif op == "lw":
                rd, imm, rs1 = args
                word = lw(rd, imm, rs1)
            elif op == "sw":
                rs2, imm, rs1 = args
                word = sw(rs2, imm, rs1)
            elif op == "beq":
                rs1, rs2, label = args
                word = beq(rs1, rs2, self.labels[label] - addr)
            elif op == "jal":
                rd, label = args
                word = jal(rd, self.labels[label] - addr)
            elif op == "jalr":
                rd, rs1, imm = args
                word = jalr(rd, rs1, imm)
            else:
                raise ValueError(op)
            words.append(word)
        return words


def build_program():
    x = REG
    p = Program()

    p.emit("lui", x["t0"], 0x80200)          # MMIO base
    p.emit("addi", x["t2"], x["zero"], 1)    # LED value
    p.emit("sw", x["t2"], 0x40, x["t0"])    # LED = 1
    p.emit("addi", x["s0"], x["zero"], 0)    # received char count

    p.label("wait_rx")
    p.emit("lw", x["t1"], 0x64, x["t0"])    # UART_STATUS
    p.emit("andi", x["t1"], x["t1"], 4)     # rx_valid
    p.emit("beq", x["t1"], x["zero"], "wait_rx")
    p.emit("lw", x["a0"], 0x68, x["t0"])    # UART_RXDATA, read clears rx_valid
    p.emit("andi", x["a0"], x["a0"], 0x0FF)

    p.emit("addi", x["s0"], x["s0"], 1)
    p.emit("sw", x["s0"], 0x20, x["t0"])    # SEG = received count
    p.emit("addi", x["t2"], x["t2"], 1)
    p.emit("sw", x["t2"], 0x40, x["t0"])    # LED increments

    p.emit("jal", x["ra"], "putc")          # echo received char
    p.emit("addi", x["a1"], x["zero"], 13)
    p.emit("beq", x["a0"], x["a1"], "send_crlf")
    p.emit("addi", x["a1"], x["zero"], 10)
    p.emit("beq", x["a0"], x["a1"], "send_crlf")
    p.emit("jal", x["zero"], "wait_rx")

    p.label("send_crlf")
    p.emit("addi", x["a0"], x["zero"], 13)
    p.emit("jal", x["ra"], "putc")
    p.emit("addi", x["a0"], x["zero"], 10)
    p.emit("jal", x["ra"], "putc")
    p.emit("jal", x["zero"], "wait_rx")

    p.label("putc")
    p.emit("lw", x["t1"], 0x64, x["t0"])    # UART_STATUS
    p.emit("andi", x["t1"], x["t1"], 2)     # tx_ready
    p.emit("beq", x["t1"], x["zero"], "putc")
    p.emit("sw", x["a0"], 0x60, x["t0"])    # UART_TXDATA
    p.emit("jalr", x["zero"], x["ra"], 0)

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
