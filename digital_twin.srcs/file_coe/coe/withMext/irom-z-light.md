# Z_LIGHT IROM test

Files:
- `gen_irom_z_light.ps1`: repeatable generator for the test image.
- `irom-z-light.coe`: generated IROM image in the same COE format as the existing `withMext/irom.coe`.

MMIO addresses reused by the program:
- `SEG_ADDR = 0x80200020`
- `LED_ADDR = 0x80200040`
- `CNT_ADDR = 0x80200050`

Counter commands reused by the program:
- start: `0x80000000`
- stop: `0xffffffff`

The program tests these Z_LIGHT instructions in order:

| Fail code | Instruction | Input(s) | Expected result |
| --- | --- | --- | --- |
| `0xbad00001` | `andn` | `rs1=0x123480f0`, `rs2=0x0f0f00aa` | `0x10308050` |
| `0xbad00002` | `orn` | `rs1=0x123480f0`, `rs2=0x0f0f00aa` | `0xf2f4fff5` |
| `0xbad00003` | `xnor` | `rs1=0x123480f0`, `rs2=0x0f0f00aa` | `0xe2c47fa5` |
| `0xbad00004` | `sext.b` | `rs1=0x000000f0` | `0xfffffff0` |
| `0xbad00005` | `sext.h` | `rs1=0x000080f0` | `0xffff80f0` |
| `0xbad00006` | `zext.h` | `rs1=0x123480f0` | `0x000080f0` |
| `0xbad00007` | `orc.b` | `rs1=0x12008000` | `0xff00ff00` |
| `0xbad00008` | `pack` | `rs1=0x123480f0`, `rs2=0x0f0f00aa` | `0x00aa80f0` |
| `0xbad00009` | `packh` | `rs1=0x123480f0`, `rs2=0x0f0f00aa` | `0x0000aaf0` |
| `0xbad0000a` | `rev8` | `rs1=0x123480f0` | `0xf0803412` |
| `0xbad0000b` | `brev8` | `rs1=0x123480f0` | `0x482c010f` |
| `0xbad0000c` | `zip` | `rs1=0x0000ffff` | `0x55555555` |
| `0xbad0000d` | `unzip` | `rs1=0x55555555` | `0x0000ffff` |
| `0xbad0000e` | `bclr` | `rs1=0x000000ff`, `rs2=3` | `0x000000f7` |
| `0xbad0000f` | `bclri` | `rs1=0x000000ff`, `shamt=3` | `0x000000f7` |
| `0xbad00010` | `bext` | `rs1=0x00000080`, `rs2=7` | `0x00000001` |
| `0xbad00011` | `bexti` | `rs1=0x00000080`, `shamt=7` | `0x00000001` |
| `0xbad00012` | `binv` | `rs1=0x00000000`, `rs2=4` | `0x00000010` |
| `0xbad00013` | `binvi` | `rs1=0x00000000`, `shamt=4` | `0x00000010` |
| `0xbad00014` | `bset` | `rs1=0x00000000`, `rs2=5` | `0x00000020` |
| `0xbad00015` | `bseti` | `rs1=0x00000000`, `shamt=5` | `0x00000020` |

Pass behavior:
- writes `0xffffffff` to `CNT_ADDR` to stop the counter,
- writes `0x90606092` to `LED_ADDR`; this matches the existing `irom-v2` check-pass pattern `0x90606090` and keeps bit 1 set for the Z extension pass lamp,
- writes `0x37000015` to `SEG_ADDR`, keeping the `37xxxxxx` display format and using `0x15` for the 21-test count.

Fail behavior:
- writes `0xffffffff` to `CNT_ADDR` to stop the counter,
- writes `0xbad000xx` to `SEG_ADDR`, where `xx` is the failed test index in the table above,
- loops forever without writing the pass LED.
