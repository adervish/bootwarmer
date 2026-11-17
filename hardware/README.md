# Bootwarmer controller board (rev C, integrated)

One board per boot. Each board carries an ESP32-C6 module, one 18650 cell, a
USB-C port for charging and flashing, one heater output, one thermistor input,
and an IMU. JLCPCB places every part except the through-hole battery holder.

Status: **unbuilt first article.** The design passes KiCad's electrical and
design-rule checks and the netlist is verified against the design file, but no
board has been made or powered. Read "Before you order" below.

## What is on the board

| Block | Parts | Notes |
|---|---|---|
| MCU | U1 (ESP32-C6-MINI-1-N4) | Bluetooth LE; built-in antenna overhangs the end of the cell |
| Battery | MPD BH-18650-PC holder on the back | The only hand-soldered part: two through-hole joints |
| Reverse-polarity protection | Q1, Q2 (AO3401A), R6 | A cell inserted backwards is blocked |
| Cell protection | U3 (DW01A), Q3, Q4 (AO3400A) | Over-discharge, over-charge, short circuit; trips at roughly 2.5-3 A |
| USB-C and charger | J1, U5, U2 (TP4056), about 0.6 A | Red = charging, green = done. Same port flashes firmware |
| 3.3 V supply | U4 (ME6211), SW1 | The slide switch enables the regulator |
| Heater output | J2, Q5 (AO3400A), R23, R24, C3 | Low-side switch, 100 Hz PWM, off by default |
| Thermistor input | J4, R21 (5.1k), C12 | 10k NTC (B3950) between the two pins |
| IMU | U6 (LSM6DS3TR-C), I2C address 0x6A | |
| Status | LED3, SW2 (BOOT) | |
| Test pads | TP1 GND, TP2 3V3, TP3 VSYS | |

Board: 107 x 27.4 mm, 2 layers, about 24 mm thick with the holder.

## Pin map

| GPIO | Net | Use |
|---|---|---|
| IO14 | HTR1 | Heater MOSFET gate, high = heat |
| IO1 | NTC1 | Thermistor divider (ADC) |
| IO0 | VBAT_SENSE | Battery voltage / 2 (ADC) |
| IO6 | VBUS_SENSE | USB present, VBUS / 2 (ADC) |
| IO7 / IO18 | SDA / SCL | IMU |
| IO19 | IMU_INT | IMU interrupt 1 |
| IO8 | LED_STAT | Status LED, low = on (strapping pin, pulled high) |
| IO9 | BOOT | Boot button to ground (strapping pin, pulled high) |
| IO12 / IO13 | USB_DN / USB_DP | USB-C data |

## Ordering from JLCPCB

Files are in `fab/`:

1. Upload `bootwarmer-gerbers.zip`. 2 layers, 1.6 mm, LeadFree HASL.
2. Turn on PCB Assembly, **Standard** type, top side. The ESP32 module and the
   IMU are not available with Economic assembly.
3. Upload `bootwarmer-bom.csv` and `bootwarmer-cpl.csv`. 54 parts are placed.
4. Confirm stock for every line. The module (C5736265) has been out of stock at
   times; the -H4 and -N8 variants of ESP32-C6-MINI-1 use the same footprint.
5. Set Confirm Parts Placement to Yes and check the placement preview.
   JLCPCB's rotation convention differs from KiCad's for some packages. Look at
   U1, U2, U3, U4, U5, U6, the SOT-23 transistors, the LEDs, J1 and SW1.
6. J2 and J4 use a JST-PH-compatible connector (CJT A2001WR-S-2P) on a footprint
   drawn for the genuine JST part. Check that they sit on their pads.

Parts you add yourself:

- **BT1**: MPD BH-18650-PC holder, soldered on the back. `+` end is at the USB end.
- Heater and thermistor leads need JST PH 2-pin plugs.

## Before you order

- **Heater resistance.** The heater runs from 3.0-4.2 V. A pad of about
  2.5-3.5 ohms gives roughly 4-6 W. Pads sized for 5 V will make about half
  their rated heat. Keep heater current under 2 A (connector rating).
- **Run time.** A 3000 mAh cell holds about 11 Wh: roughly 2 hours at a
  continuous 5 W, longer when the PID loop is cycling, less in the cold.
- **Thermal cutoff.** Firmware cuts the heater at 130 F and on any sensor
  fault, and a watchdog resets a hung controller. Nothing independent of
  firmware limits pad temperature. A 60 C thermal fuse in series with the pad,
  taped to it, is strongly recommended.
- **Unprotected flat-top 18650 cells.** Protected cells are usually too long
  for this holder. The spring contacts can bounce under hard impacts.
- **Thermistor accuracy** assumes a 3.3 V rail. Below about 3.4 V of battery
  the rail sags and readings drift; firmware stops heating at 3.3 V.
- The heater current loop is laid out by hand with wide copper; the rest is
  autorouted. Open `bootwarmer/bootwarmer.kicad_pcb` in KiCad and look it over.

## Bring-up

1. Before fitting the holder, check for shorts with a meter: VSYS to GND and
   3V3 to GND.
2. Solder the holder. Insert a cell. TP3 (VSYS) may read 0 V until the charger
   wakes the protection chip; plugging in USB once does that.
3. Switch ON. TP2 should read 3.3 V and the status LED should blink.
4. Plug in USB-C. The red LED lights while charging. Heating is disabled
   whenever USB is plugged in.
5. Flash `src/esp32c6/bootwarmer` (board: ESP32C6 Dev Module, USB CDC On Boot
   enabled). If the port does not appear, hold BOOT while switching ON.
6. Plug in a thermistor and heater, unplug USB, and connect with the app.
   A new board comes up as left; the app's control packet can reassign it.

## Regenerating

Everything is generated from `scripts/design.py`. Edit that file, then run
`./build.sh`. It rebuilds the schematic, places and autoroutes the board,
pours and stitches the ground planes, runs ERC and DRC, verifies both netlists
against the design file, and rewrites `fab/`.

Requirements: KiCad 10, Freerouting 2.5 jar at
`~/.local/share/freerouting/freerouting.jar`, and Java 25 or newer
(`brew install openjdk`).
