# MMIO UART TX/RX

This build adds a minimal MMIO UART for CPU debug output. TX has already been
validated with `Hi\r\n`; RX is a small 8N1 receiver intended for monitor and
bootloader bring-up.

## MMIO map

- `UART_TXDATA_ADDR = 0x80200060`
  - Write `wdata[7:0]` to transmit one byte.
  - If TX is busy, the write is ignored.
- `UART_STATUS_ADDR = 0x80200064`
  - Read returns `{28'b0, rx_overrun, rx_valid, tx_ready, tx_busy}`.
  - `bit0 = tx_busy`
  - `bit1 = tx_ready`
  - `bit2 = rx_valid`
  - `bit3 = rx_overrun`
- `UART_RXDATA_ADDR = 0x80200068`
  - Read returns `{24'b0, rx_data[7:0]}`.
  - Reading this address clears `rx_valid`.
- `UART_CTRL_ADDR = 0x8020006C`
  - Write `bit0 = 1` to clear `rx_valid`.
  - Write `bit1 = 1` to clear `rx_overrun`.

If a new byte arrives while `rx_valid` is still set, the latest byte replaces
the previous byte and `rx_overrun` is set.

## Minimal software check

```c
#define UART_TXDATA (*(volatile unsigned int *)0x80200060u)
#define UART_STATUS (*(volatile unsigned int *)0x80200064u)

static void uart_putc(char c) {
    while ((UART_STATUS & 0x2u) == 0) {
    }
    UART_TXDATA = (unsigned char)c;
}

void uart_hello(void) {
    uart_putc('H');
    uart_putc('i');
    uart_putc('\r');
    uart_putc('\n');
}
```

## Echo smoke test

`irom-uart-echo.coe` uses only RV32I instructions:

```c
#define UART_TXDATA (*(volatile unsigned int *)0x80200060u)
#define UART_STATUS (*(volatile unsigned int *)0x80200064u)
#define UART_RXDATA (*(volatile unsigned int *)0x80200068u)
#define LED         (*(volatile unsigned int *)0x80200040u)
#define SEG         (*(volatile unsigned int *)0x80200020u)

LED = 1;
for (;;) {
    while ((UART_STATUS & 0x4u) == 0) {
    }
    unsigned int ch = UART_RXDATA & 0xffu;
    count++;
    SEG = count;
    LED++;
    uart_putc(ch);
    if (ch == '\r' || ch == '\n') {
        uart_putc('\r');
        uart_putc('\n');
    }
}
```

Default RTL parameters are `CLK_FREQ_HZ = 260000000` and
`BAUD_RATE = 115200`. If the CPU PLL frequency changes significantly, update
the `CPU_CLK_FREQ_HZ` parameter passed from `top.sv`.
