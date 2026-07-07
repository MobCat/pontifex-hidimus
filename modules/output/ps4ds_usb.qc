// PlayStation 4 DualShock 4 — usb_device output module (Engine 4.0).
//
// Presents a virtual USB DualShock 4 over USB/IP so anything that wants a real
// DS4 over USB sees one, sourced from any input via the config. We re-pack the
// decoded signals into the DS4 USB report 0x01 and route the host's output
// report 0x05 (rumble/lightbar) back to the input device.
//
// ┌─ DESCRIPTOR STATUS ─────────────────────────────────────────────────────┐
// │ Captured from a real DualShock 4 v2 (CUH-ZCT2) with USB Device Tree      │
// │ Viewer (2026-06-19). Device 054C:09CC, bcdDevice 0100, EP0 64, strings   │
// │ "Sony Interactive Entertainment" / "Wireless Controller", no serial. The │
// │ real device is composite (3 audio interfaces + 1 HID); like ps5_usb we   │
// │ present the HID interface ONLY (audio = speaker/mic, out of scope). HID   │
// │ EPs 0x84 IN / 0x03 OUT, interrupt, 64 B, bInterval 5. The 507-byte report │
// │ descriptor below is the REAL one, extracted byte-for-byte from the dump.  │
// │ Feature reports (0x02 calib, 0x12 MAC, ...) are answered by the engine's  │
// │ feature passthrough from the physical pad — same as ps5_usb/Returnal.     │
// │                                                                            │
// │ NB the v1 (CUH-ZCT1, 054C:05C4) is NOT byte-identical: it enumerates      │
// │ HID-ONLY natively (no audio interfaces, the same shape we present here),  │
// │ its report descriptor is 483 B (vs 507), and its manufacturer string is   │
// │ "Sony Computer Entertainment" (SCE, pre-2016) vs "...Interactive..." here. │
// │ Input layout is identical, so ps4ds.qc reads both; we emulate the v2.     │
// └──────────────────────────────────────────────────────────────────────────┘

string MODULE_ID      = "ps4ds_usb";
string MODULE_NAME    = "PlayStation 4 DualShock 4 (virtual USB)";
string MODULE_VERSION = "0.1.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.0.0";
string DRIVER         = "usb_device";

// USB identity — a genuine DualShock 4 v2.
int    USB_VID          = 0x054C;
int    USB_PID          = 0x09CC;
int    USB_BCD_DEVICE   = 0x0100;
int    USB_EP0_SIZE     = 0x40;   // DS4 uses a 64-byte EP0
string USB_MANUFACTURER = "Sony Interactive Entertainment";
string USB_PRODUCT      = "Wireless Controller";
string USB_SERIAL       = "";

int _seq = 0;

void() declare_usb =
{
    // Configuration: config(9) + HID interface(9) + HID(9) + EP IN(7) + EP OUT(7)
    // = 41 (0x29). Self-powered (0xC0), 500 mA, like the real pad. Audio
    // interfaces from the composite device are omitted (HID-only).
    usb_config(
        "09 02 29 00 01 01 00 C0 FA"   // configuration, wTotalLength=0x29, 500 mA
        "09 04 00 00 02 03 00 00 00"   // interface 0: class 03 (HID), 2 endpoints
        "09 21 11 01 00 01 22 FB 01"   // HID descriptor (report-descriptor len 0x01FB = 507)
        "07 05 84 03 40 00 05"         // EP 0x84 IN,  interrupt, 64 B, 5 ms
        "07 05 03 03 40 00 05"         // EP 0x03 OUT, interrupt, 64 B, 5 ms
    );

    // Real DS4 v2 USB HID report descriptor (507 bytes), captured from the
    // physical controller (UsbTreeView, 2026-06-19). Input report 0x01 (gamepad:
    // 4 stick axes, hat, 14 buttons, vendor 6-bit, 2 trigger axes, then 54 vendor
    // bytes = timestamp/battery/IMU/touch), output report 0x05 (rumble/lightbar),
    // and the full set of vendor feature reports.
    usb_hid_report_descriptor(
        "05 01 09 05 A1 01 85 01 09 30 09 31 09 32 09 35"
        "15 00 26 FF 00 75 08 95 04 81 02 09 39 15 00 25"
        "07 35 00 46 3B 01 65 14 75 04 95 01 81 42 65 00"
        "05 09 19 01 29 0E 15 00 25 01 75 01 95 0E 81 02"
        "06 00 FF 09 20 75 06 95 01 15 00 25 7F 81 02 05"
        "01 09 33 09 34 15 00 26 FF 00 75 08 95 02 81 02"
        "06 00 FF 09 21 95 36 81 02 85 05 09 22 95 1F 91"
        "02 85 04 09 23 95 24 B1 02 85 02 09 24 95 24 B1"
        "02 85 08 09 25 95 03 B1 02 85 10 09 26 95 04 B1"
        "02 85 11 09 27 95 02 B1 02 85 12 06 02 FF 09 21"
        "95 0F B1 02 85 13 09 22 95 16 B1 02 85 14 06 05"
        "FF 09 20 95 10 B1 02 85 15 09 21 95 2C B1 02 06"
        "80 FF 85 80 09 20 95 06 B1 02 85 81 09 21 95 06"
        "B1 02 85 82 09 22 95 05 B1 02 85 83 09 23 95 01"
        "B1 02 85 84 09 24 95 04 B1 02 85 85 09 25 95 06"
        "B1 02 85 86 09 26 95 06 B1 02 85 87 09 27 95 23"
        "B1 02 85 88 09 28 95 3F B1 02 85 89 09 29 95 02"
        "B1 02 85 90 09 30 95 05 B1 02 85 91 09 31 95 03"
        "B1 02 85 92 09 32 95 03 B1 02 85 93 09 33 95 0C"
        "B1 02 85 94 09 34 95 3F B1 02 85 A0 09 40 95 06"
        "B1 02 85 A1 09 41 95 01 B1 02 85 A2 09 42 95 01"
        "B1 02 85 A3 09 43 95 30 B1 02 85 A4 09 44 95 0D"
        "B1 02 85 F0 09 47 95 3F B1 02 85 F1 09 48 95 3F"
        "B1 02 85 F2 09 49 95 0F B1 02 85 A7 09 4A 95 01"
        "B1 02 85 A8 09 4B 95 01 B1 02 85 A9 09 4C 95 08"
        "B1 02 85 AA 09 4E 95 01 B1 02 85 AB 09 4F 95 39"
        "B1 02 85 AC 09 50 95 39 B1 02 85 AD 09 51 95 0B"
        "B1 02 85 AE 09 52 95 01 B1 02 85 AF 09 53 95 02"
        "B1 02 85 B0 09 54 95 3F B1 02 85 E0 09 57 95 02"
        "B1 02 85 B3 09 55 95 3F B1 02 85 B4 09 55 95 3F"
        "B1 02 85 B5 09 56 95 3F B1 02 85 D0 09 58 95 3F"
        "B1 02 85 D4 09 59 95 3F B1 02 C0"
    );

    in_endpoint(0x84);
    out_endpoint(0x03);
};

void() declare_signals =
{
    report_len(64);

    // Feedback the host writes to the virtual DS4; routed back to the physical
    // pad via [ps4ds_usb.feedback] in the config. Names match ps4ds input module.
    out_feedback("RUMBLE_HEAVY",  0, 255);  // left / strong / low-freq motor
    out_feedback("RUMBLE_SOFT",   0, 255);  // right / weak / high-freq motor
    out_feedback("LED_R",         0, 255);
    out_feedback("LED_G",         0, 255);
    out_feedback("LED_B",         0, 255);
    out_feedback("LED_FLASH_ON",  0, 255);
    out_feedback("LED_FLASH_OFF", 0, 255);

    // D-pad: bits 0-3 -> compass nibble in byte[5] low nibble (pack()).
    out_btn("BTN_DPAD_UP",    0x0001);
    out_btn("BTN_DPAD_DOWN",  0x0002);
    out_btn("BTN_DPAD_LEFT",  0x0004);
    out_btn("BTN_DPAD_RIGHT", 0x0008);

    // Face buttons: bits 4-7 -> byte[5] high nibble.
    out_btn("BTN_SQUARE",   0x0010);
    out_btn("BTN_CROSS",    0x0020);
    out_btn("BTN_CIRCLE",   0x0040);
    out_btn("BTN_TRIANGLE", 0x0080);

    // Shoulder + menu + clicks: bits 8-15 -> byte[6].
    out_btn("BTN_L1",      0x0100);
    out_btn("BTN_R1",      0x0200);
    out_btn("BTN_L2",      0x0400);
    out_btn("BTN_R2",      0x0800);
    out_btn("BTN_SHARE",   0x1000);
    out_btn("BTN_OPTIONS", 0x2000);
    out_btn("BTN_L3",      0x4000);
    out_btn("BTN_R3",      0x8000);

    // System buttons: bits 16-17 -> byte[7] (PS, touchpad click).
    out_btn("BTN_PS",       0x00010000);
    out_btn("BTN_TOUCHPAD", 0x00020000);

    // Battery charging flag at bit 24.
    out_btn("BATTERY_CHARGING", 0x01000000);

    out_axis("LEFT_STICK_X",  0, 255);
    out_axis("LEFT_STICK_Y",  0, 255);
    out_axis("RIGHT_STICK_X", 0, 255);
    out_axis("RIGHT_STICK_Y", 0, 255);
    out_axis("L2_ANALOG",     0, 255);
    out_axis("R2_ANALOG",     0, 255);

    out_axis("GYRO_X",  -32768, 32767);
    out_axis("GYRO_Y",  -32768, 32767);
    out_axis("GYRO_Z",  -32768, 32767);
    out_axis("ACCEL_X", -32768, 32767);
    out_axis("ACCEL_Y", -32768, 32767);
    out_axis("ACCEL_Z", -32768, 32767);

    out_axis("TOUCH1_X", 0, 1919);
    out_axis("TOUCH1_Y", 0, 942);
    out_axis("TOUCH2_X", 0, 1919);
    out_axis("TOUCH2_Y", 0, 942);

    out_axis("BATTERY_LEVEL", 0, 100);
};

void() pack =
{
    _seq = (_seq + 1) & 0xFF;

    set_report_byte(0, 0x01);   // report ID
    set_report_byte(1, get_axis("LEFT_STICK_X")  & 0xFF);
    set_report_byte(2, get_axis("LEFT_STICK_Y")  & 0xFF);
    set_report_byte(3, get_axis("RIGHT_STICK_X") & 0xFF);
    set_report_byte(4, get_axis("RIGHT_STICK_Y") & 0xFF);

    local int btns = get_buttons();

    // Byte 5: d-pad compass nibble (bits 0-3) + face buttons (bits 4-7).
    local int u = btns        & 1;
    local int d = (btns >> 1) & 1;
    local int l = (btns >> 2) & 1;
    local int r = (btns >> 3) & 1;
    local int dpad_nibble = 8;       // neutral
    if (u | d | l | r) {
        if (r) {
            dpad_nibble = 2 - u + d;
        } else {
            if (l) {
                dpad_nibble = 6 + u - d;
            } else {
                dpad_nibble = 4 * d;
            }
        }
    }
    set_report_byte(5, dpad_nibble | (btns & 0xF0));
    set_report_byte(6, (btns >> 8) & 0xFF);
    // Byte 7: PS (bit 0), touchpad (bit 1), 6-bit report counter in bits 2-7.
    set_report_byte(7, ((btns >> 16) & 0x03) | ((_seq & 0x3F) << 2));

    set_report_byte(8, get_axis("L2_ANALOG") & 0xFF);
    set_report_byte(9, get_axis("R2_ANALOG") & 0xFF);

    // Bytes 10-11: timestamp (free-running from the counter).
    set_report_word(10, _seq);

    // IMU: gyro at 13-18, accel at 19-24 (signed int16 LE).
    set_report_word(13, get_axis("GYRO_X"));
    set_report_word(15, get_axis("GYRO_Y"));
    set_report_word(17, get_axis("GYRO_Z"));
    set_report_word(19, get_axis("ACCEL_X"));
    set_report_word(21, get_axis("ACCEL_Y"));
    set_report_word(23, get_axis("ACCEL_Z"));

    // Byte 30: battery (bits 3:0 = level/10, bit 4 = charging/cable).
    local int batt_level = get_axis("BATTERY_LEVEL") / 10;
    local int batt_charging = 0;
    if (btns & 0x01000000) { batt_charging = 1; }
    set_report_byte(30, (batt_level & 0x0F) | (batt_charging << 4));

    // Touchpad finger 1 (bytes 35-38). Centre (960,471) = not touching.
    local int t1x = get_axis("TOUCH1_X");
    local int t1y = get_axis("TOUCH1_Y");
    local int t1_flag = 0x80;
    if (t1x == 960) {
        if (t1y != 471) { t1_flag = 0x00; }
    } else {
        t1_flag = 0x00;
    }
    set_report_byte(35, t1_flag | (_seq & 0x7F));
    set_report_byte(36, t1x & 0xFF);
    set_report_byte(37, ((t1x >> 8) & 0x0F) | ((t1y & 0x0F) << 4));
    set_report_byte(38, (t1y >> 4) & 0xFF);

    // Touchpad finger 2 (bytes 39-42).
    local int t2x = get_axis("TOUCH2_X");
    local int t2y = get_axis("TOUCH2_Y");
    local int t2_flag = 0x80;
    if (t2x == 960) {
        if (t2y != 471) { t2_flag = 0x00; }
    } else {
        t2_flag = 0x00;
    }
    set_report_byte(39, t2_flag | (_seq & 0x7F));
    set_report_byte(40, t2x & 0xFF);
    set_report_byte(41, ((t2x >> 8) & 0x0F) | ((t2y & 0x0F) << 4));
    set_report_byte(42, (t2y >> 4) & 0xFF);
};

// Host -> device: the DS4 USB output report 0x05 (rumble + lightbar). Decode it
// into out_feedback signals the config routes back to the real pad. Byte map
// mirrors ps4ds.qc write_feedback() USB path.
void(bytes raw) on_output =
{
    if (raw[0] != 0x05) { return; }

    set_out_feedback("RUMBLE_SOFT",   raw[4]);   // right / weak motor
    set_out_feedback("RUMBLE_HEAVY",  raw[5]);   // left  / strong motor
    set_out_feedback("LED_R",         raw[6]);
    set_out_feedback("LED_G",         raw[7]);
    set_out_feedback("LED_B",         raw[8]);
    set_out_feedback("LED_FLASH_ON",  raw[9]);
    set_out_feedback("LED_FLASH_OFF", raw[10]);
};
