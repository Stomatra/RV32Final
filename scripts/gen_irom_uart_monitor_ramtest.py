from pathlib import Path

from gen_irom_uart_monitor_lite import (
    REG,
    Program,
    b_type,
    check_signed,
    emit_led_patterns,
    emit_li,
    emit_print,
    emit_print_crlf_prompt,
    emit_print_hex32,
    emit_putc_const,
    emit_seg_patterns,
    i_type,
    j_type,
    r_type,
    s_type,
    shift_i_type,
    u_type,
)


OUT = Path("digital_twin.srcs/sources_1/imports/test_src/irom-uart-monitor-ramtest.coe")
DRAM_BASE = 0x8010_0000
DRAM_END = 0x8013_FFFF
RAM_TEST_WORDS = 256
DUMP_WORDS = 16
ADDR_XOR_PATTERN = 0x5A5A_5A5A


class ProgramRamtest(Program):
    def resolve(self):
        words = []
        for pc, (op, args) in enumerate(self.items):
            addr = pc * 4
            if op == "add":
                rd, rs1, rs2 = args
                word = r_type(0x00, rs2, rs1, 0x0, rd, 0x33)
            elif op == "xor":
                rd, rs1, rs2 = args
                word = r_type(0x00, rs2, rs1, 0x4, rd, 0x33)
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


def emit_command_dispatch(p):
    x = REG
    commands = [
        ("?", "disp_help", "cmd_help"),
        ("s", "disp_status", "cmd_status"),
        ("l", "disp_led", "cmd_led"),
        ("g", "disp_seg", "cmd_seg"),
        ("r", "disp_ram_r", "cmd_ram"),
        ("m", "disp_ram_m", "cmd_ram"),
        ("d", "disp_dump", "cmd_dump"),
        ("w", "disp_write_pattern", "cmd_write_pattern"),
        ("v", "disp_verify_pattern", "cmd_verify_pattern"),
        ("c", "disp_clear", "cmd_clear"),
        ("t", "disp_timer", "cmd_timer"),
        ("\r", "disp_ignore_cr", "monitor_loop"),
        ("\n", "disp_ignore_lf", "monitor_loop"),
    ]
    for ch, label, _ in commands:
        emit_li(p, x["t1"], ord(ch))
        p.emit("beq", x["a0"], x["t1"], label)
    p.emit("jal", x["zero"], "cmd_unknown")
    for _, label, target in commands:
        p.label(label)
        p.emit("jal", x["zero"], target)


def emit_ram_helpers(p):
    x = REG

    p.label("ram_write_const256")
    p.emit("addi", x["t0"], x["s1"], 0)
    emit_li(p, x["t1"], 0)
    emit_li(p, x["t2"], RAM_TEST_WORDS)
    p.label("ram_write_const256_loop")
    p.emit("sw", x["a1"], 0, x["t0"])
    p.emit("addi", x["t0"], x["t0"], 4)
    p.emit("addi", x["t1"], x["t1"], 1)
    p.emit("bne", x["t1"], x["t2"], "ram_write_const256_loop")
    p.emit("jalr", x["zero"], x["ra"], 0)

    p.label("ram_verify_const256")
    p.emit("addi", x["t0"], x["s1"], 0)
    emit_li(p, x["t1"], 0)
    emit_li(p, x["t2"], RAM_TEST_WORDS)
    p.label("ram_verify_const256_loop")
    p.emit("lw", x["a2"], 0, x["t0"])
    p.emit("bne", x["a2"], x["a1"], "ram_verify_const256_fail")
    p.emit("addi", x["t0"], x["t0"], 4)
    p.emit("addi", x["t1"], x["t1"], 1)
    p.emit("bne", x["t1"], x["t2"], "ram_verify_const256_loop")
    emit_li(p, x["a0"], 0)
    p.emit("jalr", x["zero"], x["ra"], 0)
    p.label("ram_verify_const256_fail")
    p.emit("addi", x["s6"], x["t0"], 0)
    p.emit("addi", x["s7"], x["a1"], 0)
    p.emit("addi", x["t3"], x["a2"], 0)
    emit_li(p, x["a0"], 1)
    p.emit("jalr", x["zero"], x["ra"], 0)

    p.label("ram_write_addr_pattern256")
    p.emit("addi", x["t0"], x["s1"], 0)
    emit_li(p, x["t1"], 0)
    emit_li(p, x["t2"], RAM_TEST_WORDS)
    emit_li(p, x["t4"], ADDR_XOR_PATTERN)
    p.label("ram_write_addr_pattern256_loop")
    p.emit("xor", x["a1"], x["t0"], x["t4"])
    p.emit("sw", x["a1"], 0, x["t0"])
    p.emit("addi", x["t0"], x["t0"], 4)
    p.emit("addi", x["t1"], x["t1"], 1)
    p.emit("bne", x["t1"], x["t2"], "ram_write_addr_pattern256_loop")
    p.emit("jalr", x["zero"], x["ra"], 0)

    p.label("ram_verify_addr_pattern256")
    p.emit("addi", x["t0"], x["s1"], 0)
    emit_li(p, x["t1"], 0)
    emit_li(p, x["t2"], RAM_TEST_WORDS)
    emit_li(p, x["t4"], ADDR_XOR_PATTERN)
    p.label("ram_verify_addr_pattern256_loop")
    p.emit("xor", x["a1"], x["t0"], x["t4"])
    p.emit("lw", x["a2"], 0, x["t0"])
    p.emit("bne", x["a2"], x["a1"], "ram_verify_addr_pattern256_fail")
    p.emit("addi", x["t0"], x["t0"], 4)
    p.emit("addi", x["t1"], x["t1"], 1)
    p.emit("bne", x["t1"], x["t2"], "ram_verify_addr_pattern256_loop")
    emit_li(p, x["a0"], 0)
    p.emit("jalr", x["zero"], x["ra"], 0)
    p.label("ram_verify_addr_pattern256_fail")
    p.emit("addi", x["s6"], x["t0"], 0)
    p.emit("addi", x["s7"], x["a1"], 0)
    p.emit("addi", x["t3"], x["a2"], 0)
    emit_li(p, x["a0"], 1)
    p.emit("jalr", x["zero"], x["ra"], 0)


def emit_ram_pass(p):
    x = REG
    p.label("cmd_ram_pass")
    emit_li(p, x["s2"], 0x03030303)
    p.emit("sw", x["s2"], 0x40, x["s0"])
    emit_li(p, x["s3"], 0xA55A0001)
    p.emit("sw", x["s3"], 0x20, x["s0"])
    emit_print(p, "\r\nRAM PASS")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")


def emit_ram_fail(p):
    x = REG
    p.label("cmd_ram_fail")
    emit_li(p, x["s2"], 0x00000001)
    p.emit("sw", x["s2"], 0x40, x["s0"])
    emit_li(p, x["s3"], 0xBAD00001)
    p.emit("sw", x["s3"], 0x20, x["s0"])
    emit_print(p, "\r\nRAM FAIL\r\nADDR=0x")
    p.emit("addi", x["a0"], x["s6"], 0)
    p.emit("jal", x["ra"], "print_hex32")
    emit_print(p, "\r\nEXP =0x")
    p.emit("addi", x["a0"], x["s7"], 0)
    p.emit("jal", x["ra"], "print_hex32")
    emit_print(p, "\r\nGOT =0x")
    p.emit("addi", x["a0"], x["t3"], 0)
    p.emit("jal", x["ra"], "print_hex32")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")


def emit_ram_test_command(p):
    x = REG
    p.label("cmd_ram")
    emit_li(p, x["a1"], 0x00000000)
    p.emit("jal", x["ra"], "ram_write_const256")
    emit_li(p, x["a1"], 0x00000000)
    p.emit("jal", x["ra"], "ram_verify_const256")
    p.emit("bne", x["a0"], x["zero"], "cmd_ram_to_fail")

    emit_li(p, x["a1"], 0xFFFFFFFF)
    p.emit("jal", x["ra"], "ram_write_const256")
    emit_li(p, x["a1"], 0xFFFFFFFF)
    p.emit("jal", x["ra"], "ram_verify_const256")
    p.emit("bne", x["a0"], x["zero"], "cmd_ram_to_fail")

    p.emit("jal", x["ra"], "ram_write_addr_pattern256")
    p.emit("jal", x["ra"], "ram_verify_addr_pattern256")
    p.emit("bne", x["a0"], x["zero"], "cmd_ram_to_fail")
    p.emit("jal", x["zero"], "cmd_ram_pass")

    p.label("cmd_ram_to_fail")
    p.emit("jal", x["zero"], "cmd_ram_fail")


def emit_dump_command(p):
    x = REG
    p.label("cmd_dump")
    emit_print(p, "\r\nDRAM 0x80100000\r\n")
    p.emit("addi", x["t0"], x["s1"], 0)
    emit_li(p, x["t4"], 0)
    emit_li(p, x["t5"], DUMP_WORDS)
    p.label("cmd_dump_loop")
    p.emit("addi", x["a0"], x["t0"], 0)
    p.emit("jal", x["ra"], "print_hex32")
    emit_print(p, ": ")
    p.emit("lw", x["a0"], 0, x["t0"])
    p.emit("jal", x["ra"], "print_hex32")
    emit_print(p, "\r\n")
    p.emit("addi", x["t0"], x["t0"], 4)
    p.emit("addi", x["t4"], x["t4"], 1)
    p.emit("bne", x["t4"], x["t5"], "cmd_dump_loop")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")


def emit_write_verify_commands(p):
    x = REG
    p.label("cmd_write_pattern")
    p.emit("jal", x["ra"], "ram_write_addr_pattern256")
    emit_print(p, "\r\nWR OK")
    emit_print_crlf_prompt(p)
    p.emit("jal", x["zero"], "monitor_loop")

    p.label("cmd_verify_pattern")
    p.emit("jal", x["ra"], "ram_verify_addr_pattern256")
    p.emit("bne", x["a0"], x["zero"], "cmd_verify_to_fail")
    p.emit("jal", x["zero"], "cmd_ram_pass")
    p.label("cmd_verify_to_fail")
    p.emit("jal", x["zero"], "cmd_ram_fail")


def build_program():
    x = REG
    p = ProgramRamtest()

    p.emit("lui", x["s0"], 0x80200)
    p.emit("lui", x["s1"], 0x80100)
    emit_li(p, x["s2"], 0x00000001)
    emit_li(p, x["s3"], 0x00000000)
    emit_li(p, x["s4"], 1)
    emit_li(p, x["s5"], 0)
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
        "r ram smoke\r\n"
        "m ram test\r\n"
        "d dump memory\r\n"
        "w write pattern\r\n"
        "v verify pattern\r\n"
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

    emit_ram_test_command(p)
    emit_dump_command(p)
    emit_write_verify_commands(p)
    emit_ram_pass(p)
    emit_ram_fail(p)

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
    emit_ram_helpers(p)

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
    print(f"DRAM_RANGE=0x{DRAM_BASE:08X}-0x{DRAM_END:08X}")
    print(f"RAM_TEST_WORDS={RAM_TEST_WORDS}")
