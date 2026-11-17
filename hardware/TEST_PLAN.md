# Bootwarmer rev C test plan

Work through the stages in order and stop at the first failure. Nothing in this
design has been built before, so the early stages are about finding assembly
or design faults before a lithium cell is involved.

Equipment: multimeter, USB-C cable and charger, computer with the Arduino IDE,
a bench supply with a current limit (strongly preferred for stages 2-3), a
3.3 ohm 10 W resistor as a dummy heater, a thermometer, the phone app.

During every powered stage the firmware prints one line every 2 seconds on the
USB serial port (115200 baud):

    T=71.3F set=70F mode=5 power=0% bat=3.92V usb=1 faults=0x00 imu=1 ble=0

Fault bits: 0x01 thermistor open, 0x02 thermistor shorted, 0x04 over-temp,
0x08 low battery, 0x10 USB present (heater held off).

## Stage 0 - Bare board, nothing connected

| # | Check | Pass |
|---|---|---|
| 0.1 | Look over every part against the silkscreen: U1 module square to its pads, no solder bridges on U1, U6, U5, J1 | Nothing skewed or bridged |
| 0.2 | Polarity marks: U2 pin 1 toward C1/R3; LED cathodes toward U2 (LED1, LED2) and toward the board centre (LED3) | Match |
| 0.3 | Resistance TP3 (VSYS) to TP1 (GND) | Above 10 k ohm (it climbs as capacitors charge) |
| 0.4 | Resistance TP2 (3V3) to TP1 (GND) | Above 1 k ohm |
| 0.5 | Resistance across HEATER connector pins | Open circuit |
| 0.6 | Resistance battery `+` pad to battery `-` pad | Above 10 k ohm |

## Stage 1 - USB power only, no cell, holder not yet soldered

| # | Check | Pass |
|---|---|---|
| 1.1 | Switch OFF. Plug in USB-C. Nothing gets hot. | U2 at most slightly warm |
| 1.2 | TP3 (VSYS) | About 4.0-4.3 V (the charger running with no cell; LEDs may flicker) |
| 1.3 | TP2 (3V3) with switch OFF | 0 V |
| 1.4 | Switch ON. TP2 | 3.25-3.35 V |
| 1.5 | Status LED (LED3) | Blinking |
| 1.6 | Computer sees a new USB serial port | Yes. If not, hold BOOT while switching ON and retry |
| 1.7 | Flash `src/esp32c6/bootwarmer` (ESP32C6 Dev Module, USB CDC On Boot enabled) | Upload succeeds |
| 1.8 | Serial log | Lines every 2 s; `imu=1`; `usb=1`; `faults` includes 0x10 and 0x01 (no thermistor) |
| 1.9 | Plug in the thermistor. Log `T=` | Within 3 F of room temperature; fault 0x01 clears |
| 1.10 | Short the NTC connector pins briefly | Fault 0x02 appears, then clears |

## Stage 2 - Battery input, using a bench supply in place of the cell

Solder the holder. Clip the supply to the holder contacts: 3.8 V, current limit
0.3 A. USB unplugged.

| # | Check | Pass |
|---|---|---|
| 2.1 | **Reverse polarity first:** supply connected backwards, switch ON | Supply current near 0 mA; TP3 near 0 V; nothing warm |
| 2.2 | Correct polarity. TP3 | May be 0 V until woken. Plug USB in for a second, unplug. Then TP3 within 0.1 V of the supply |
| 2.3 | Switch ON. Supply current, heater off | Roughly 20-80 mA |
| 2.4 | Switch OFF. Supply current | Under 0.2 mA |
| 2.5 | Switch ON. Serial log is not available without USB, so connect with the app | App connects; temperature reads correctly |
| 2.6 | Plug in USB as well. Log `bat=` | Within 0.1 V of the supply voltage |

## Stage 3 - Heater drive, dummy load

Raise the supply limit to 2.5 A. Plug the 3.3 ohm resistor into HEATER. USB
unplugged (heating is disabled while USB is present). Use the app's power
button to step through the forced modes.

| # | Check | Pass |
|---|---|---|
| 3.1 | Mode Off / 0 % | Supply current unchanged from 2.3 |
| 3.2 | 25 %, 50 %, 100 % | Extra current about 0.29 A, 0.58 A, 1.15 A at 3.8 V |
| 3.3 | At 100 % for 5 minutes, touch-test Q5, Q1, Q2, Q3, Q4, both connectors | Warm at most; nothing too hot to hold a finger on |
| 3.4 | Voltage TP3 to the HEATER connector pin 1 at 100 % | Under 0.1 V drop |
| 3.5 | Plug in USB during heating | Heater current drops to zero; fault 0x10 |
| 3.6 | Unplug the thermistor during heating | Heater off within a second; fault 0x01 |
| 3.7 | Track-temperature mode, setpoint 10 F above room, thermistor taped to the resistor | Heats, settles within about 3 F of setpoint, power falls back from 100 % |
| 3.8 | Warm the thermistor past 130 F (hair dryer) | Heater off; fault 0x04; recovers when it cools |
| 3.9 | Lower the supply slowly to 3.25 V | Heater off, fault 0x08. Raise to 3.6 V: heating resumes |
| 3.10 | Switch OFF while heating | Heater current zero immediately |
| 3.11 | Short the HEATER pins with the supply limited to 2.5 A | Output cuts off. Remove the short, plug USB briefly to reset, board recovers |

## Stage 4 - Real cell and charging

Never leave a charging cell unattended during these tests.

| # | Check | Pass |
|---|---|---|
| 4.1 | Insert a partly discharged cell the right way round, tap USB to wake | TP3 equals cell voltage |
| 4.2 | Plug in USB | Red LED on. Cell voltage rises slowly |
| 4.3 | Charge current (inline USB meter, switch OFF) | About 0.55-0.65 A while the cell is below 4.1 V |
| 4.4 | U2 temperature during charge | Hot but touchable; the board around it warm |
| 4.5 | Leave to finish | Green LED on, red off; cell 4.15-4.25 V |
| 4.6 | Insert the cell backwards, switch ON, no USB | Nothing happens; nothing warm. Remove within a few seconds |
| 4.7 | Tap and shake the board with the cell fitted, switch ON | No resets (status LED keeps its rhythm, app stays connected) |

## Stage 5 - Real heater pad, on the bench

| # | Check | Pass |
|---|---|---|
| 5.1 | Measure the pad's resistance | 2.5-3.5 ohm for 4-6 W. Under 1.9 ohm will exceed the 2 A connector rating |
| 5.2 | Pad in open air, thermistor taped to it, track mode at 95 F | Reaches and holds setpoint; note overshoot |
| 5.3 | 100 % forced for 20 minutes, pad between two layers of sock fabric | Thermistor and an independent thermometer stay under 130 F, or the cutoff trips |
| 5.4 | If fitted: thermal fuse opens when the pad is overheated deliberately | Heater dead until the fuse is replaced |
| 5.5 | Run from full charge in track mode until the low-battery cutoff | Record the run time |

## Stage 6 - Two boots and the app

| # | Check | Pass |
|---|---|---|
| 6.1 | Both boards on | App connects to both |
| 6.2 | Assign one board to the right side, power-cycle it | Left and right columns each follow their own board |
| 6.3 | Set different targets left and right | Each board follows its own target |
| 6.4 | Move a board | IMU readings change; about 9.8 m/s2 on one axis at rest |
| 6.5 | Range: phone in a jacket pocket, boards at boot height, cell fitted | Stays connected. Then walk away and note where it drops and that it reconnects |
| 6.6 | Switch a board off and on | App reconnects on its own; setpoint is remembered |

## Stage 7 - Conditions

| # | Check | Pass |
|---|---|---|
| 7.1 | 30 minutes in a freezer (in a bag), then switch ON | Boots, connects, heats |
| 7.2 | Run time at freezer temperature | Record; expect noticeably less than 5.5 |
| 7.3 | In the boot, a full session | No resets, no hot spots, connectors stay seated |
