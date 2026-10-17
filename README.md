# FPGA SPI Protocol: ADXL345 Tilt Display

A from-scratch Verilog SPI master that talks to the onboard **ADXL345 accelerometer** of a Terasic **DE10-Lite** (Intel MAX 10) board. The board's tilt along the X axis is shown as a smoothly fading "bubble level" on the 10 red LEDs.

## Overview

```
 MAX10_CLK1_50 ──► adxl345_controller ──► led_driver ──► LEDR[9:0]
                     │            ▲
                     ▼            │ INT2 (DATA_READY)
                  spi_master ◄────┘
                     │
        SCLK / CS_N / SDI / SDO
                     ▼
                  ADXL345
```

| File | Description |
|------|-------------|
| [`USE_ACCEL.v`](USE_ACCEL.v) | Top-level module: connects board pins to the controller |
| [`spi_master.v`](spi_master.v) | 16-bit SPI master, mode 3 (CPOL=1, CPHA=1), 500 kHz SCLK from the 50 MHz clock |
| [`adxl345_controller.v`](adxl345_controller.v) | State machine that configures the ADXL345 and reads X-axis data on each data-ready interrupt |
| [`led_driver.v`](led_driver.v) | Maps the signed X reading to LED positions with PWM brightness and smooth fading |
| [`btn_pulse.v`](btn_pulse.v) | Push-button synchronizer / rising-edge pulse helper (not used in the current top level) |
| [`USE_ACCEL.sdc`](USE_ACCEL.sdc) | Timing constraints (50 MHz / 10 MHz clocks) |
| [`USE_ACCEL.qpf`](USE_ACCEL.qpf), [`USE_ACCEL.qsf`](USE_ACCEL.qsf) | Quartus project and pin assignments |
| [`stp2.stp`](stp2.stp) | Signal Tap logic analyzer setup used to debug the SPI bus on hardware |

## How it works

### SPI master (`spi_master.v`)
- Divides the 50 MHz system clock to a 1 MHz enable tick; SCLK toggles on each tick, so SCLK runs at 500 kHz (well under the ADXL345's 5 MHz limit).
- Idles with `CS_N` high and `SCLK` high (SPI mode 3, as required by the ADXL345).
- Shifts a 16-bit word out MSB-first (8-bit command/address + 8-bit data), shifts MOSI on the falling edge, and samples MISO on the rising edge.
- Raises `done` for exactly one 50 MHz cycle when the transfer completes, with the received byte on `rx_data`.

### ADXL345 controller (`adxl345_controller.v`)
1. Waits about 20 ms after reset for the sensor to power up.
2. Writes `0x2E = 0x80` (INT_ENABLE: DATA_READY).
3. Writes `0x2F = 0x80` (INT_MAP: DATA_READY → INT2).
4. Writes `0x2D = 0x08` (POWER_CTL: measurement mode).
5. Waits for INT2 (passed through a 3-flop synchronizer), then reads `DATAX0` (`0xB2`) and `DATAX1` (`0xB3`). Reading those registers clears the interrupt.
6. Waits for INT2 to fall again, then repeats. At the default 100 Hz output data rate this happens every 10 ms.

Each SPI transaction uses a handshake: the controller asserts `start`, then waits in a dedicated state until the master's `done` pulse before issuing the next command.

### LED driver (`led_driver.v`)
- Takes the 10-bit two's-complement X value, computes its absolute value, and uses the top bits as a tilt magnitude.
- Lights a bright center LED with dimmer neighbors that move left or right according to the tilt direction.
- Each LED has an 8-bit brightness target. The displayed brightness steps toward the target once per millisecond to create the fade, and a shared 8-bit PWM counter drives the LEDs.

## Hardware

- **Board:** Terasic DE10-Lite
- **FPGA:** Intel MAX 10 `10M50DAF484C7G`
- **Sensor:** Analog Devices ADXL345 (onboard, 4-wire SPI)
- **Reset:** `KEY[0]` (active low). `HEX0` shows a reset indicator while reset is held.

## Building

1. Open `USE_ACCEL.qpf` in **Quartus Prime Lite 23.1** (any recent Lite version that supports MAX 10 should work).
2. Run **Processing → Start Compilation**.
3. Program the board with **Tools → Programmer** using `USE_ACCEL.sof`.
4. Tilt the board left and right to see the LEDs follow.

Compiled result (including the Signal Tap instance): about 1,124 logic elements (2% of the device) and timing met at 50 MHz.

## Author

Justin Dubreuil
