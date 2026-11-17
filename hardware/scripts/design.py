"""Single source of truth for the per-boot Bootwarmer controller (rev C, integrated).

One board per boot: ESP32-C6-MINI-1 module, 18650 holder, charger and cell
protection, one heater output, one thermistor input, IMU, USB-C.  The only
part not placed by the assembler is the through-hole battery holder.

Every component is listed once with its symbol, footprint, JLCPCB/LCSC part
number, pin->net map and board placement.  gen_sch.py and gen_pcb.py both
read this file, so the schematic and the PCB cannot drift apart.

Pin keys are matched against the pin NUMBER first, then the pin NAME (a name
that occurs on several pins, e.g. GND, assigns all of them).  NC = no connect.
Placement is (x_mm, y_mm, rotation_deg) on the top side.  The board spans
BOARD_X0..BOARD_W in x and 0..BOARD_H in y; x = 0 is the west end of the
battery holder, and the USB-C port sits in the strip west of it.  The 18650
holder is the only bottom-side part.
"""

BOARD_X0 = -9.0                   # west edge (USB-C lives between here and the holder)
BOARD_W, BOARD_H = 98.0, 27.4
CY = BOARD_H / 2                  # 18650 holder centre line
ANTENNA_KEEPOUT_X = 92.8          # no copper east of this line (module antenna)
NC = None

R0603 = "Resistor_SMD:R_0603_1608Metric"
C0603 = "Capacitor_SMD:C_0603_1608Metric"
C0805 = "Capacitor_SMD:C_0805_2012Metric"
LED0603 = "LED_SMD:LED_0603_1608Metric"
SOT23 = "Package_TO_SOT_SMD:SOT-23"
JSTPH = "Connector_JST:JST_PH_S2B-PH-SM4-TB_1x02-1MP_P2.00mm_Horizontal"
TP = "TestPoint:TestPoint_Pad_D1.5mm"

# LCSC part numbers (looked up against the JLCPCB catalogue, Nov 2026)
L_R = {"5.1k": "C23186", "10k": "C25804", "100k": "C25803", "1k": "C21190",
       "100R": "C22775", "2k": "C22975"}
L_C = {"100nF": "C14663", "10uF": "C19702", "1uF": "C15849", "22uF": "C45783"}

COMPONENTS = []


def add(ref, group, sym, fp, value, lcsc, pins, pos, extra=None, side="F", assemble=True, mpn=""):
    COMPONENTS.append(dict(ref=ref, group=group, sym=sym, fp=fp, value=value, lcsc=lcsc,
                           pins=pins, pos=pos, extra=extra or {}, side=side,
                           assemble=assemble, mpn=mpn or value))


def R(ref, group, value, a, b, pos):
    add(ref, group, "Device:R", R0603, value, L_R[value], {"1": a, "2": b}, pos)


def C(ref, group, value, a, b, pos, fp=C0603):
    add(ref, group, "Device:C", fp, value, L_C[value], {"1": a, "2": b}, pos)


# ---------------------------------------------------------------- battery
add("BT1", "Battery", "Device:Battery_Cell", "Battery:BatteryHolder_MPD_BH-18650-PC",
    "18650 holder", "", {"+": "CELL_P", "-": "CELL_N"}, (3.7, CY, 0), side="B",
    assemble=False, mpn="MPD BH-18650-PC (hand solder)")
# Reverse-polarity protection: two P-FETs in parallel in the + lead.
# Gate referenced to the cell's own minus terminal so a reversed cell can
# never turn them on, even with USB power present.
for ref, pos in (("Q1", (7.5, CY - 5.5, 180)), ("Q2", (7.5, CY + 5.5, 180))):
    add(ref, "Battery", "Transistor_FET:AO3401A", SOT23, "AO3401A", "C15127",
        {"G": "PF_GATE", "S": "VSYS", "D": "CELL_P"}, pos)
R("R6", "Battery", "10k", "PF_GATE", "CELL_N", (8.5, CY, 90))
# Cell protection (over-discharge, over-charge, over-current, short circuit)
add("U3", "Battery", "Battery_Management:DW01A", "Package_TO_SOT_SMD:SOT-23-6", "DW01A", "C351410",
    {"OD": "DW_OD", "CS": "DW_CS", "OC": "DW_OC", "TD": NC, "VCC": "DW_VCC", "GND": "CELL_N"},
    (72.2, 10.6, 0))
add("Q3", "Battery", "Transistor_FET:AO3400A", SOT23, "AO3400A", "C20917",
    {"G": "DW_OD", "S": "CELL_N", "D": "PROT_MID"}, (76.6, 17.3, 270))
add("Q4", "Battery", "Transistor_FET:AO3400A", SOT23, "AO3400A", "C20917",
    {"G": "DW_OC", "S": "GND", "D": "PROT_MID"}, (72.6, 17.3, 270))
R("R7", "Battery", "1k", "DW_CS", "GND", (71.5, 7.6, 0))
R("R8", "Battery", "100R", "VSYS", "DW_VCC", (68.3, 7.6, 0))
C("C4", "Battery", "100nF", "DW_VCC", "CELL_N", (74.7, 7.6, 0))
# battery voltage to the ADC
R("R15", "Battery", "100k", "VSYS", "VBAT_SENSE", (68.3, 5.2, 0))
R("R16", "Battery", "100k", "VBAT_SENSE", "GND", (71.5, 5.2, 0))
C("C10", "Battery", "100nF", "VBAT_SENSE", "GND", (74.7, 5.2, 0))

# ---------------------------------------------------------------- USB-C + charger
add("J1", "USB / charger", "Connector:USB_C_Receptacle_USB2.0_16P",
    "Connector_USB:USB_C_Receptacle_HRO_TYPE-C-31-M-12", "USB-C", "C165948",
    {"VBUS": "VBUS", "GND": "GND", "CC1": "CC1", "CC2": "CC2", "D+": "USB_DP", "D-": "USB_DN",
     "SBU1": NC, "SBU2": NC, "SHIELD": "GND"}, (BOARD_X0 + 3.3, CY, 270), mpn="HRO TYPE-C-31-M-12")
R("R1", "USB / charger", "5.1k", "CC1", "GND", (-5.4, 6.0, 0))
R("R2", "USB / charger", "5.1k", "CC2", "GND", (-5.4, 21.4, 0))
add("U5", "USB / charger", "Power_Protection:USBLC6-2SC6", "Package_TO_SOT_SMD:SOT-23-6",
    "USBLC6-2SC6", "C7519",
    {"I/O1": "USB_DP", "I/O2": "USB_DN", "GND": "GND", "VBUS": "VBUS"}, (-5.4, 24.4, 0))
add("U2", "USB / charger", "Battery_Management:TP4056-42-ESOP8",
    "Package_SO:SOIC-8-1EP_3.9x4.9mm_P1.27mm_EP2.41x3.3mm", "TP4056", "C16581",
    {"TEMP": "GND", "PROG": "PROG", "GND": "GND", "V_{CC}": "VBUS", "BAT": "VSYS",
     "~{STDBY}": "STDBY_N", "~{CHRG}": "CHRG_N", "CE": "VBUS", "EPAD": "GND"},
    (20.0, 22.3, 0), mpn="TP4056-42-ESOP8")
R("R3", "USB / charger", "2k", "PROG", "GND", (14.5, 22.3, 90))        # ~0.6 A charge
C("C1", "USB / charger", "10uF", "VBUS", "GND", (20.0, 18.4, 0))
C("C2", "USB / charger", "10uF", "VSYS", "GND", (25.5, 24.3, 90))
add("LED1", "USB / charger", "Device:LED", LED0603, "RED (charging)", "C2286",
    {"A": "LED1_A", "K": "CHRG_N"}, (28.5, 21.0, 0), mpn="KT-0603R")
R("R4", "USB / charger", "1k", "VBUS", "LED1_A", (31.7, 21.0, 0))
add("LED2", "USB / charger", "Device:LED", LED0603, "GREEN (charged)", "C965804",
    {"A": "LED2_A", "K": "STDBY_N"}, (28.5, 22.8, 0), mpn="XL-1608UGC-04")
R("R5", "USB / charger", "1k", "VBUS", "LED2_A", (31.7, 22.8, 0))
R("R19", "USB / charger", "100k", "VBUS", "VBUS_SENSE", (56.0, 19.4, 0))
R("R20", "USB / charger", "100k", "VBUS_SENSE", "GND", (59.4, 19.4, 0))

# ---------------------------------------------------------------- power switch + 3.3 V
add("SW1", "3V3 supply", "Switch:SW_SPDT", "Button_Switch_SMD:SW_SPDT_Shouhan_MSK12C02",
    "ON/OFF", "C431540", {"A": "VSYS", "B": "LDO_EN", "C": NC}, (6.5, 2.1, 180),
    extra={"SH": "GND"}, mpn="MSK12C02")
R("R9", "3V3 supply", "100k", "LDO_EN", "GND", (48.0, 9.2, 0))
add("U4", "3V3 supply", "Regulator_Linear:ME6211C33M5", "Package_TO_SOT_SMD:SOT-23-5",
    "ME6211C33", "C82942",
    {"V_{IN}": "VSYS", "V_{SS}": "GND", "CE": "LDO_EN", "NC": NC, "V_{OUT}": "3V3"},
    (48.0, 5.5, 0), mpn="ME6211C33M5G-N")
C("C5", "3V3 supply", "1uF", "VSYS", "GND", (44.3, 5.5, 270))
C("C6", "3V3 supply", "1uF", "3V3", "GND", (51.7, 5.5, 270))

# ---------------------------------------------------------------- MCU
# ESP32-C6-MINI-1, antenna end pointing east and overhanging the cell.
MCU_X = 86.5
add("U1", "MCU", "RF_Module:ESP32-C6-MINI-1", "RF_Module:ESP32-C6-MINI-1",
    "ESP32-C6-MINI-1-N4", "C5736265",
    {"3V3": "3V3", "EN": "EN", "GND": "GND", "NC": NC,
     "IO0": "VBAT_SENSE",          # ADC1_CH0
     "IO1": "NTC1",                # ADC1_CH1
     "IO6": "VBUS_SENSE",          # ADC1_CH6
     "IO7": "SDA", "IO18": "SCL", "IO19": "IMU_INT",
     "IO12": "USB_DN", "IO13": "USB_DP",
     "IO14": "HTR1",
     "IO8": "LED_STAT",            # strapping pin, pulled high
     "IO9": "BOOT",                # strapping pin, pulled high; button to ground
     "IO2": NC, "IO3": NC, "IO4": NC, "IO5": NC, "IO15": NC,
     "IO20": NC, "IO21": NC, "IO22": NC, "IO23": NC, "RXD0": NC, "TXD0": NC},
    (MCU_X, CY, 270))
C("C8", "MCU", "100nF", "3V3", "GND", (88.9, 5.1, 90))
C("C7", "MCU", "10uF", "3V3", "GND", (90.7, 5.1, 90))
R("R10", "MCU", "10k", "EN", "3V3", (84.9, 5.1, 90))
C("C9", "MCU", "1uF", "EN", "GND", (83.1, 5.1, 90))
R("R12", "MCU", "10k", "3V3", "LED_STAT", (70.0, 23.4, 0))
R("R14", "MCU", "10k", "3V3", "BOOT", (73.2, 23.4, 0))
add("SW2", "MCU", "Switch:SW_Push", "Button_Switch_SMD:SW_Push_1P1T_XKB_TS-1187A",
    "BOOT", "C318884", {"1": "BOOT", "2": "GND"}, (86.5, 24.0, 0), mpn="TS-1187A-B-A-B")
add("LED3", "MCU", "Device:LED", LED0603, "GREEN (status)", "C965804",
    {"A": "LED3_A", "K": "LED_STAT"}, (70.0, 21.5, 0), mpn="XL-1608UGC-04")
R("R13", "MCU", "1k", "3V3", "LED3_A", (73.2, 21.5, 0))

# ---------------------------------------------------------------- heater output
add("J2", "Heater", "Connector_Generic:Conn_01x02", JSTPH, "HEATER", "C225233",
    {"1": "VSYS", "2": "HTR1_SW"}, (21.0, 5.3, 180), extra={"MP": "GND"},
    mpn="CJT A2001WR-S-2P (JST PH compatible)")
add("Q5", "Heater", "Transistor_FET:AO3400A", SOT23, "AO3400A", "C20917",
    {"G": "HTR1_GATE", "S": "GND", "D": "HTR1_SW"}, (20.0, 12.6, 90))
R("R23", "Heater", "100R", "HTR1", "HTR1_GATE", (15.9, 11.5, 0))
R("R24", "Heater", "10k", "HTR1_GATE", "GND", (15.9, 13.3, 180))       # heater off while the MCU boots
C("C3", "Heater", "22uF", "VSYS", "GND", (27.0, 12.6, 270), fp=C0805)

# ---------------------------------------------------------------- thermistor input
# 10k NTC (B3950) from 3V3 to the ADC pin, 5.1k to ground.
add("J4", "Thermistor", "Connector_Generic:Conn_01x02", JSTPH, "NTC", "C225233",
    {"1": "3V3", "2": "NTC1"}, (31.5, 5.3, 180), extra={"MP": "GND"},
    mpn="CJT A2001WR-S-2P (JST PH compatible)")
R("R21", "Thermistor", "5.1k", "NTC1", "GND", (30.3, 11.5, 0))
C("C12", "Thermistor", "100nF", "NTC1", "GND", (33.7, 11.5, 0))

# ---------------------------------------------------------------- IMU
add("U6", "IMU", "Sensor_Motion:LSM6DS3", "Package_LGA:LGA-14_3x2.5mm_P0.5mm_LayoutBorder3x4y",
    "LSM6DS3TR-C", "C967633",
    {"SDO/SA0": "GND", "SDX": "GND", "SCX": "GND", "INT1": "IMU_INT", "VDDIO": "3V3",
     "GND": "GND", "VDD": "3V3", "INT2": NC, "NC": NC, "CS": "3V3", "SCL": "SCL", "SDA": "SDA"},
    (61.0, 11.0, 0))
C("C14", "IMU", "100nF", "3V3", "GND", (64.3, 11.0, 90))
C("C15", "IMU", "10uF", "3V3", "GND", (57.2, 11.0, 90))
R("R27", "IMU", "10k", "3V3", "SDA", (58.0, 5.2, 0))
R("R28", "IMU", "10k", "3V3", "SCL", (61.2, 5.2, 0))

# ---------------------------------------------------------------- test pads
for ref, net, x in (("TP1", "GND", 3.0), ("TP2", "3V3", 6.5), ("TP3", "VSYS", 10.0)):
    add(ref, "Test pads", "Connector:TestPoint", TP, net, "", {"1": net}, (x, 25.3, 0), assemble=False)

POWER_NETS = ["VSYS", "VBUS"]
POWER_WIDTH = 0.4                 # autorouted width; the heater loop also gets hand-placed heavy copper
VBUS_WIDTH = 0.3                  # USB-C VBUS pads are only 0.3 mm wide; <1 A charge current
SIGNAL_WIDTH = 0.25

# ---------------------------------------------------------------- hand-placed copper
# The heater current loop is laid out by hand (the autorouter only does the
# small-signal and light power wiring):
#   cell+ -> Q1||Q2 -> VSYS pour (bottom) -> heater connector -> heater ->
#   Q5 -> GND pours -> Q4 -> Q3 -> cell-
COPPER = [
    # cell + to the two reverse-polarity FET drains
    ('track', "CELL_P", [(3.7, CY), (6.56, CY - 5.5)], 1.2),
    ('track', "CELL_P", [(3.7, CY), (6.56, CY + 5.5)], 1.2),
    # FET sources down to the bottom-layer VSYS pour
    ('track', "VSYS", [(8.44, CY - 6.45), (9.9, CY - 6.8)], 0.8),
    ('track', "VSYS", [(8.44, CY - 6.45), (9.9, CY - 5.7)], 0.8),
    ('via', "VSYS", 9.9, CY - 6.8), ('via', "VSYS", 9.9, CY - 5.7),
    ('track', "VSYS", [(8.44, CY + 4.55), (9.9, CY + 4.0)], 0.8),
    ('track', "VSYS", [(8.44, CY + 4.55), (9.9, CY + 5.1)], 0.8),
    ('via', "VSYS", 9.9, CY + 4.0), ('via', "VSYS", 9.9, CY + 5.1),
    # VSYS pour up to heater connector pin 1 and the bulk capacitor
    ('track', "VSYS", [(22.0, 8.9), (22.0, 10.75)], 0.8), ('via', "VSYS", 22.0, 10.75),
    ('track', "VSYS", [(27.0, 11.65), (27.0, 10.1)], 0.8), ('via', "VSYS", 27.0, 10.1),
    # VSYS pour up to the regulator input and the VSYS test pad
    ('track', "VSYS", [(46.86, 4.55), (45.6, 4.55)], 0.5), ('via', "VSYS", 45.6, 4.55, 0.6, 0.3),
    ('track', "VSYS", [(9.9, CY + 5.1), (10.0, 25.3)], 0.4),
    # heater connector pin 2 to the low-side FET drain
    ('track', "HTR1_SW", [(20.0, 8.9), (20.0, 11.66)], 1.0),
    # low-side FET source into the ground pours
    ('track', "GND", [(20.95, 13.54), (20.95, 16.4)], 0.6), ('via', "GND", 20.95, 16.4),
    ('track', "GND", [(20.95, 16.4), (22.05, 16.4)], 0.6), ('via', "GND", 22.05, 16.4),
    # protection FETs: ground -> Q4 -> Q3 -> cell -
    ('track', "GND", [(71.65, 16.36), (70.3, 16.0)], 0.6), ('via', "GND", 70.3, 16.0),
    ('track', "GND", [(71.65, 16.36), (70.3, 17.2)], 0.6), ('via', "GND", 70.3, 17.2),
    ('track', "PROT_MID", [(72.6, 18.24), (76.6, 18.24)], 1.0),
    ('track', "CELL_N", [(75.65, 16.36), (76.2, 14.8)], 1.0),
    # light-current runs laid by hand
    # VSYS feed east from the pour on the bottom layer: regulator input, then R8 / R15
    ('btrack', "VSYS", [(28.65, 8.9), (45.6, 8.9), (45.6, 4.55)], 0.6),
    ('btrack', "VSYS", [(45.6, 8.9), (65.0, 8.9), (66.3, 7.6)], 0.4),
    ('track', "VSYS", [(67.48, 7.6), (66.3, 7.6)], 0.3), ('via', "VSYS", 66.3, 7.6, 0.6, 0.3),
    ('track', "VSYS", [(67.48, 7.6), (67.48, 5.2)], 0.3),
    # power switch feed, and charger output back to the VSYS test pad / pour
    ('track', "VSYS", [(8.75, 4.05), (9.9, CY - 6.8)], 0.4),
    ('track', "VSYS", [(22.48, 24.21), (23.6, 25.12), (25.5, 25.12)], 0.5),
    ('track', "VSYS", [(25.5, 25.12), (24.6, 26.3), (11.0, 26.3), (10.0, 25.3)], 0.5),
    # ground pads that would otherwise sit in an isolated patch of top copper
    ('track', "GND", [(72.32, 7.6), (72.6, 6.3)], 0.3), ('via', "GND", 72.6, 6.3, 0.6, 0.3),
    ('track', "GND", [(61.25, 11.91), (61.25, 13.3)], 0.25), ('via', "GND", 61.25, 13.3, 0.6, 0.3),
    # R6 (P-FET gate reference) to the cell minus terminal at the far end
    ('track', "CELL_N", [(8.5, 12.88), (9.5, 11.5), (13.9, 11.5)], 0.25),
    ('via', "CELL_N", 13.9, 11.5, 0.6, 0.3),
    ('btrack', "CELL_N", [(13.9, 11.5), (14.5, 11.9), (64.5, 11.9), (65.5, 10.9), (74.6, 10.9), (75.8, 12.6)], 0.25),
]
# bottom-layer VSYS pour: column under Q1/Q2 plus a band under the heater connector
VSYS_ZONE = [(7.0, 3.6), (29.0, 3.6), (29.0, 11.2), (10.7, 11.2), (10.7, 19.9), (7.0, 19.9)]
# top-layer areas left free of ground pour (copper there would be an unconnected island)
NO_POUR_TOP = [[(3.7, 0.8), (9.3, 0.8), (9.3, 3.4), (3.7, 3.4)]]

# Bottom-layer areas the autorouter may not run traces through, so the VSYS
# pour and a ground-return spine stay unbroken from the heater FET to the
# battery protection FETs.  (Vias are still allowed.)
BOTTOM_NO_ROUTE = [
    [(7.0, 3.6), (28.3, 3.6), (28.3, 11.2), (10.7, 11.2), (10.7, 19.9), (7.0, 19.9)],   # VSYS pour, less the feed exit
    [(11.5, 15.7), (71.5, 15.7), (71.5, 18.0), (11.5, 18.0)],
]
# thin strips just inside the board edge so the autorouter keeps copper off the edge
EDGE_STRIPS = [[(BOARD_X0, 0), (BOARD_W, 0), (BOARD_W, 0.45), (BOARD_X0, 0.45)],
               [(BOARD_X0, BOARD_H - 0.45), (BOARD_W, BOARD_H - 0.45), (BOARD_W, BOARD_H), (BOARD_X0, BOARD_H)],
               [(BOARD_X0, 0), (BOARD_X0 + 0.45, 0), (BOARD_X0 + 0.45, BOARD_H), (BOARD_X0, BOARD_H)]]

# silkscreen: (text, x, y, size)
SILK = [
    ("HEATER", 21.0, 1.5, 1.0), ("NTC", 31.5, 1.5, 1.0),
    ("ON", 12.6, 2.6, 0.8), ("OFF", 0.6, 4.9, 0.8), ("CHG", 28.5, 19.6, 0.8),
    ("BOOTWARMER rev C", 44.0, 14.0, 1.2), ("BOOT", 80.0, 25.6, 0.8), ("USB", -5.4, 3.6, 0.9),
    ("+", 2.2, 10.3, 1.6), ("-", 78.6, 9.8, 1.4),
]
