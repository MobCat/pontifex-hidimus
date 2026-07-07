// PlayStation 5 DualSense — usb_device output module (Engine 4.0).
//
// Presents a virtual USB DualSense over USB/IP so games that only accept a
// DualSense over USB (e.g. Returnal) see one — while the real controller is
// connected over Bluetooth and feeds us through the ps5ds input module. We just
// re-pack the already-decoded signals into the USB report 0x01 layout, and
// route the game's output report 0x02 (rumble/LED) back to the real pad.
//
// USB input report 0x01 (64 bytes) — see pack() for the byte map.
// USB output report 0x02 (host → device) — decoded in on_output().
//
// ┌─ DESCRIPTOR STATUS ───────────────────────────────────────────────────────┐
// │ Confirmed from a USB capture (2026-06-13): device descriptor matches this │
// │ module exactly (054C:0CE6, bcdDevice 0100, iSerial 0). Real config has 4  │
// │ interfaces (3 = audio for the speaker/mic + advanced haptics, 1 = HID at  │
// │ interface 3) with HID EPs 0x84 IN / 0x03 OUT at bInterval 6. We present a │
// │ single HID interface (no audio) — fine for input + standard rumble/LED/   │
// │ adaptive-trigger output report 0x02; audio-PCM haptics are out of scope.  │
// │                                                                           │
// │ The 289-byte HID report descriptor below is the REAL one, captured from   │
// │ the physical DualSense. We present a single HID interface (the audio      │
// │ interfaces are omitted; audio-PCM haptics are out of scope for now).      │
// └───────────────────────────────────────────────────────────────────────────┘

string MODULE_ID      = "ps5_usb";
string MODULE_NAME    = "PlayStation 5 DualSense (virtual USB)";
string MODULE_VERSION = "0.1.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.0.0";
string DRIVER         = "usb_device";

// USB identity — a genuine DualSense.
int    USB_VID          = 0x054C;
int    USB_PID          = 0x0CE6;
int    USB_BCD_DEVICE   = 0x0100;
int    USB_EP0_SIZE     = 0x40;   // DualSense uses a 64-byte EP0
string USB_MANUFACTURER = "Sony Interactive Entertainment";
string USB_PRODUCT      = "DualSense Wireless Controller";
string USB_SERIAL       = "";

int _seq = 0;

void() declare_usb =
{
    // Configuration: config(9) + HID interface(9) + HID(9) + EP IN(7) + EP OUT(7)
    // = 41 (0x29). DualSense USB endpoints: 0x84 IN, 0x03 OUT (interrupt).
    usb_config(
        "09 02 29 00 01 01 00 80 FA"   // configuration, wTotalLength=0x29, 500 mA
        "09 04 00 00 02 03 00 00 00"   // interface 0: class 03 (HID)
        "09 21 11 01 00 01 22 21 01"   // HID descriptor (report-descriptor len 0x0121 = 289)
        "07 05 84 03 40 00 06"         // EP 0x84 IN,  interrupt, 64 B, 6 ms (real)
        "07 05 03 03 40 00 06"         // EP 0x03 OUT, interrupt, 64 B, 6 ms (real)
    );

    // Real DualSense USB HID report descriptor (289 bytes), captured from the
    // physical controller (ps5ds_filtered1.pcapng, 2026-06-13). Declares input
    // report 0x01 (gamepad: 6 axes, hat, 15 buttons, then vendor IMU/touch),
    // output report 0x02 (47 B: rumble/LED/adaptive triggers), and the feature
    // reports (0x05 calibration, 0x09 pairing, 0x20 firmware, etc.).
    usb_hid_report_descriptor(
        "05 01 09 05 A1 01 85 01 09 30 09 31 09 32 09 35"
        "09 33 09 34 15 00 26 FF 00 75 08 95 06 81 02 06"
        "00 FF 09 20 95 01 81 02 05 01 09 39 15 00 25 07"
        "35 00 46 3B 01 65 14 75 04 95 01 81 42 65 00 05"
        "09 19 01 29 0F 15 00 25 01 75 01 95 0F 81 02 06"
        "00 FF 09 21 95 0D 81 02 06 00 FF 09 22 15 00 26"
        "FF 00 75 08 95 34 81 02 85 02 09 23 95 2F 91 02"
        "85 05 09 33 95 28 B1 02 85 08 09 34 95 2F B1 02"
        "85 09 09 24 95 13 B1 02 85 0A 09 25 95 1A B1 02"
        "85 0B 09 41 95 29 B1 02 85 0C 09 42 95 29 B1 02"
        "85 20 09 26 95 3F B1 02 85 21 09 27 95 04 B1 02"
        "85 22 09 40 95 3F B1 02 85 80 09 28 95 3F B1 02"
        "85 81 09 29 95 3F B1 02 85 82 09 2A 95 09 B1 02"
        "85 83 09 2B 95 3F B1 02 85 84 09 2C 95 3F B1 02"
        "85 85 09 2D 95 02 B1 02 85 A0 09 2E 95 01 B1 02"
        "85 E0 09 2F 95 3F B1 02 85 F0 09 30 95 3F B1 02"
        "85 F1 09 31 95 3F B1 02 85 F2 09 32 95 0F B1 02"
        "85 F4 09 35 95 3F B1 02 85 F5 09 36 95 03 B1 02"
        "C0"
    );

    in_endpoint(0x84);
    out_endpoint(0x03);
};

void() declare_signals =
{
    report_len(64);

    // Feedback the game writes to the virtual DualSense; routed back to the
    // physical pad via [ps5_usb.feedback] in the config.
    out_feedback("RUMBLE_HEAVY", 0, 255);
    out_feedback("RUMBLE_SOFT",  0, 255);
    out_feedback("LED_R",        0, 255);
    out_feedback("LED_G",        0, 255);
    out_feedback("LED_B",        0, 255);
    out_feedback("MIC_LED",      0, 2);
    out_feedback("LED_P_OUTER",  0, 1);
    out_feedback("LED_P_INNER",  0, 1);
    out_feedback("LED_P_CENTRE", 0, 1);
    out_feedback("LED_P_BRIGHTNESS", 0, 2);
    // valid_flag0 from the game's report — which features it's updating this
    // frame (rumble bit 0, right-trigger bit 2, left-trigger bit 3). Passed
    // through so the controller enables exactly what the game asked for.
    out_feedback("FEATURE_FLAGS", 0, 255);
    // Adaptive-trigger effect blocks (11 bytes each: 1 mode + 10 params),
    // passed through verbatim as blob feedback.
    out_feedback_blob("TRIGGER_RIGHT", 11);
    out_feedback_blob("TRIGGER_LEFT",  11);

    // D-pad: bits 0-3 of get_buttons(), packed into byte[8] nibble in pack().
    out_btn("BTN_DPAD_UP",    0x0001);
    out_btn("BTN_DPAD_DOWN",  0x0002);
    out_btn("BTN_DPAD_LEFT",  0x0004);
    out_btn("BTN_DPAD_RIGHT", 0x0008);

    // Face buttons: bits 4-7 -> byte[8] high nibble.
    out_btn("BTN_SQUARE",   0x0010);
    out_btn("BTN_CROSS",    0x0020);
    out_btn("BTN_CIRCLE",   0x0040);
    out_btn("BTN_TRIANGLE", 0x0080);

    // Shoulder + menu: bits 8-15 -> byte[9].
    out_btn("BTN_L1",      0x0100);
    out_btn("BTN_R1",      0x0200);
    out_btn("BTN_L2",      0x0400);
    out_btn("BTN_R2",      0x0800);
    out_btn("BTN_CREATE",  0x1000);
    out_btn("BTN_OPTIONS", 0x2000);
    out_btn("BTN_L3",      0x4000);
    out_btn("BTN_R3",      0x8000);

    // System buttons: bits 16-18 -> byte[10].
    out_btn("BTN_PS",       0x00010000);
    out_btn("BTN_TOUCHPAD", 0x00020000);
    out_btn("BTN_MUTE",     0x00040000);

    // Battery charging flag at bit 24 (kept clear of byte[10]).
    out_btn("BATTERY_CHARGING", 0x01000000);

    out_axis("LEFT_STICK_X",  0, 255);
    out_axis("LEFT_STICK_Y",  0, 255);
    out_axis("RIGHT_STICK_X", 0, 255);
    out_axis("RIGHT_STICK_Y", 0, 255);
    out_axis("L2_ANALOG",     0, 255);
    out_axis("R2_ANALOG",     0, 255);

    out_axis("TOUCH1_X", 0, 1919);
    out_axis("TOUCH1_Y", 0, 1079);
    out_axis("TOUCH2_X", 0, 1919);
    out_axis("TOUCH2_Y", 0, 1079);

    out_axis("BATTERY_LEVEL", 0, 100);
};

void() pack =
{
    _seq = (_seq + 1) & 0xFF;

    set_report_byte(0, 0x01);
    set_report_byte(1, get_axis("LEFT_STICK_X")  & 0xFF);
    set_report_byte(2, get_axis("LEFT_STICK_Y")  & 0xFF);
    set_report_byte(3, get_axis("RIGHT_STICK_X") & 0xFF);
    set_report_byte(4, get_axis("RIGHT_STICK_Y") & 0xFF);
    set_report_byte(5, get_axis("L2_ANALOG")     & 0xFF);
    set_report_byte(6, get_axis("R2_ANALOG")     & 0xFF);
    set_report_byte(7, 0x00);

    local int btns = get_buttons();

    // Byte 8: d-pad compass nibble (bits 0-3) + face buttons (bits 4-7).
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
    set_report_byte(8, dpad_nibble | (btns & 0xF0));
    set_report_byte(9, (btns >> 8) & 0xFF);
    set_report_byte(10, (btns >> 16) & 0x07);
    set_report_byte(11, _seq);

    // Bytes 12-32: gyro/accel/IMU — not decoded by the input module yet (zero).

    // Touchpad finger 1 (bytes 33-36). Centre (960,540) = not touching.
    local int t1x = get_axis("TOUCH1_X");
    local int t1y = get_axis("TOUCH1_Y");
    local int t1_flag = 0x80;
    if (t1x == 960) {
        if (t1y != 540) { t1_flag = 0x00; }
    } else {
        t1_flag = 0x00;
    }
    set_report_byte(33, t1_flag | (_seq & 0x7F));
    set_report_byte(34, t1x & 0xFF);
    set_report_byte(35, ((t1x >> 8) & 0x0F) | ((t1y & 0x0F) << 4));
    set_report_byte(36, (t1y >> 4) & 0xFF);

    // Touchpad finger 2 (bytes 37-40).
    local int t2x = get_axis("TOUCH2_X");
    local int t2y = get_axis("TOUCH2_Y");
    local int t2_flag = 0x80;
    if (t2x == 960) {
        if (t2y != 540) { t2_flag = 0x00; }
    } else {
        t2_flag = 0x00;
    }
    set_report_byte(37, t2_flag | (_seq & 0x7F));
    set_report_byte(38, t2x & 0xFF);
    set_report_byte(39, ((t2x >> 8) & 0x0F) | ((t2y & 0x0F) << 4));
    set_report_byte(40, (t2y >> 4) & 0xFF);

    // Byte 53: battery (bits 3:0 = level/10, bit 4 = charging).
    local int batt_level = get_axis("BATTERY_LEVEL") / 10;
    local int batt_charging = 0;
    if (btns & 0x01000000) { batt_charging = 1; }
    set_report_byte(53, (batt_level & 0x0F) | (batt_charging << 4));
};

// Host → device: the game's DualSense USB output report 0x02 (rumble, LED, etc).
// Decode it into out_feedback signals that the config routes back to the real
// controller. Offsets mirror ps5ds.qc's USB write_feedback() byte map.
void(bytes raw) on_output =
{
    if (raw[0] != 0x02) { return; }

    // Pass the game's valid_flag0 through (carries the trigger-enable bits), and
    // the two adaptive-trigger blocks verbatim. USB output 0x02: right trigger at
    // byte 11, left at byte 22 (11 bytes each).
    set_out_feedback("FEATURE_FLAGS", raw[1]);
    set_out_feedback_blob("TRIGGER_RIGHT", raw, 11, 11);
    set_out_feedback_blob("TRIGGER_LEFT",  raw, 22, 11);

    set_out_feedback("RUMBLE_SOFT",  raw[3]);
    set_out_feedback("RUMBLE_HEAVY", raw[4]);
    set_out_feedback("MIC_LED",      raw[9]);
    set_out_feedback("LED_P_BRIGHTNESS", raw[43]);
    set_out_feedback("LED_R", raw[45]);
    set_out_feedback("LED_G", raw[46]);
    set_out_feedback("LED_B", raw[47]);

    // Player-LED bitmask at byte[44] → OUTER/INNER/CENTRE pair signals.
    local int leds = raw[44];
    if (leds & 0x11) { set_out_feedback("LED_P_OUTER",  1); } else { set_out_feedback("LED_P_OUTER",  0); }
    if (leds & 0x0A) { set_out_feedback("LED_P_INNER",  1); } else { set_out_feedback("LED_P_INNER",  0); }
    if (leds & 0x04) { set_out_feedback("LED_P_CENTRE", 1); } else { set_out_feedback("LED_P_CENTRE", 0); }
};
