// PlayStation 4 DualShock 4. Monolithic input module for phidimus.
// Handles both USB (report 0x01) and Bluetooth (report 0x11) from one module,
// the same way ps5ds.qc (DualSense) does.

// The engine detects which transport is connected after Open() and sets IS_BT:
//   IS_BT = 0  ->  USB path        (input report 0x01, output report 0x05)
//   IS_BT = 1  ->  Bluetooth path  (input report 0x11, output report 0x11 + CRC32)

// USB vs BT byte layout differences
// BT input report 0x11 prepends TWO bytes before the standard control data
// (0x11 report id is raw[0]; raw[1]=flags ~0xC0, raw[2]=report counter). So every
// field offset shifts by +2 relative to USB (DS5 was only +1 — DS4 is +2).
//   USB raw[n]  ->  BT raw[n+2]   for sticks, buttons, triggers, motion, touch
//
// STATUS (2026-06-18): USB is HARDWARE-VERIFIED — sticks, triggers, all buttons,
// dpad, gyro, touch and the lightbar/rumble all work on real CUH-ZCT1 / ZCT2 pads.
//
// BLUETOOTH IS BLOCKED ON WINDOWS (not a module bug) — and it is a read-ACCESS
// wall, not the pad being silent. A Steam Big Picture BT capture (2026-06-19)
// shows the DS4 AUTO-STREAMS the basic report 0x01 (sticks+buttons, 20-byte
// frames; no motion/touch) the moment it connects, with ZERO host setup. So the
// pad is NOT dormant. Our --hids saw "frame 0" because Windows binds the DS4 as
// its native "Wireless Controller" and holds the interrupt-input channel: our
// exclusive open is refused ("used by another process") and shared reads error
// out, so the stream never reaches our HID handle. Steam reads it via the OS
// gamepad API, not a raw HID handle. This is the DS4-over-BT-on-Windows wall
// (what DS4Windows fights with exclusive-mode + HidHide). On the Windows SDK
// bench, use USB. Where we own the transport (Linux/phidimus-pi) the basic 0x01
// arrives for free, and setup() below UPGRADES to the full 0x11 (motion/touch).
//
// BT power-off is an HCI link Disconnect (reason 0x13), confirmed for both DS4
// and DS5 in the Steam captures — NOT a HID report (no DS4 power-off report
// exists). Trivial on the Pi (we own the stack); on Windows it needs a BT/OS API.

string MODULE_ID      = "ps4ds";
string MODULE_NAME    = "PlayStation 4 DualShock 4";
string MODULE_VERSION = "0.1.0";   // DRAFT — input from docs; capture to confirm
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.0.0";
string DRIVER         = "hid_input";

// No TRANSPORT. Driver opens whichever connection is available (USB preferred).
// IS_BT is set to 1 by the engine after Open() when Bluetooth is detected.
int IS_BT = 0;
// BT_FEEDBACK_LEN: engine resizes FeedbackBuf from 32 (USB 0x05) to 78 (BT 0x11).
int BT_FEEDBACK_LEN = 78;
// OUTPUT_REPORT_LEN_BT: engine zero-pads the 78-byte BT report to 547 for WriteFile.
int OUTPUT_REPORT_LEN_BT = 547;

// STALL_TIMEOUT_MS: the DS4 streams continuously (motion packets even when idle),
// so going silent this long means the link dropped. Engine reconnects and
// re-selects the best transport (USB preferred). Same rationale as ps5ds.qc.
int STALL_TIMEOUT_MS = 2000;

// s16le combines two little-endian bytes into a signed 16-bit value (IMU).
int(int lo, int hi) s16le =
{
    local int v = lo | (hi << 8);
    if (v >= 32768) { v = v - 65536; }
    return v;
};

void() declare_devices =
// DualShock 4 family + a few common third-party DS4-protocol pads. VID/PID list
// cross-referenced against joypad-os sony_ds4.c (Apache-2.0). Confirm any clone
// before trusting it — some "DS4" clones use a different report layout entirely.
{
//  add_device(VID, PID, "Product name");
    add_device(0x054C, 0x05C4, "DualShock 4 v1 (CUH-ZCT1)");
    add_device(0x054C, 0x09CC, "DualShock 4 v2 (CUH-ZCT2)");
    add_device(0x054C, 0x0BA0, "DualShock 4 USB Wireless Adapter");
    add_device(0x0F0D, 0x005E, "HORI FightingCommander (PS4)");
    add_device(0x0F0D, 0x00EE, "HORI PS4 Mini Wired Gamepad");
    add_device(0x1532, 0x0401, "Razer Panthera (PS4)");
    add_device(0x0C12, 0x0EF7, "Brook PS4 adapter");
    add_device(0x0738, 0x8384, "Mad Catz FightStick TE2 (PS4)");
};

void() declare_signals =
{
    // Feedback buffer size. Engine grows this to BT_FEEDBACK_LEN on BT connect.
    feedback_len(32);

    // Feedback signals (output to the controller) — same names over USB and BT.
    feedback("RUMBLE_HEAVY", 0, 255);   // large / left  / low-frequency motor
    feedback("RUMBLE_SOFT",  0, 255);   // small / right / high-frequency motor
    feedback("LED_R", 0, 255);          // lightbar red
    feedback("LED_G", 0, 255);          // lightbar green
    feedback("LED_B", 0, 255);          // lightbar blue

    // Lightbar blink. The bar repeatedly shows the LED_R/G/B colour for
    // LED_FLASH_ON, then goes dark for LED_FLASH_OFF — each in units of ~10 ms
    // (e.g. ON=180 ~1.8 s lit, OFF=50 ~0.5 s dark). BOTH must be non-zero to
    // blink: LED_FLASH_OFF=0 means a steady colour (no dark phase), which is why
    // LED_FLASH_ON appears to "do nothing" on its own. The colour shown during
    // the lit phase is always LED_R/G/B — there is no separate flash colour.
    // (Hardware-observed on a real DS4 2026-06-18.)
    feedback("LED_FLASH_ON",  0, 255);  // lit  phase duration (x~10ms); needs FLASH_OFF>0 to blink
    feedback("LED_FLASH_OFF", 0, 255);  // dark phase duration (x~10ms); 0 = steady colour

    // Digital buttons
    btn("BTN_CROSS");
    btn("BTN_CIRCLE");
    btn("BTN_SQUARE");
    btn("BTN_TRIANGLE");
    btn("BTN_L1");
    btn("BTN_R1");
    btn("BTN_L2");
    btn("BTN_R2");
    btn("BTN_SHARE");
    btn("BTN_OPTIONS");
    btn("BTN_L3");
    btn("BTN_R3");
    btn("BTN_PS");
    btn("BTN_TOUCHPAD");
    btn("BTN_DPAD_UP");
    btn("BTN_DPAD_DOWN");
    btn("BTN_DPAD_LEFT");
    btn("BTN_DPAD_RIGHT");

    // Analog sticks and triggers (0:255, centre = 128)
    axis("LEFT_STICK_X",  0, 255);
    axis("LEFT_STICK_Y",  0, 255);
    axis("RIGHT_STICK_X", 0, 255);
    axis("RIGHT_STICK_Y", 0, 255);
    axis("L2_ANALOG",     0, 255);
    axis("R2_ANALOG",     0, 255);

    // IMU — gyroscope and accelerometer, raw signed int16.
    // VERIFY axis order/direction/scale with --probe (DS4 motion order is not as
    // universally documented as the buttons; confirm against a real pad).
    axis("GYRO_X",  -32768, 32767);
    axis("GYRO_Y",  -32768, 32767);
    axis("GYRO_Z",  -32768, 32767);
    axis("ACCEL_X", -32768, 32767);
    axis("ACCEL_Y", -32768, 32767);
    axis("ACCEL_Z", -32768, 32767);

    // Touchpad — DS4 pad is 1920 x 942. VERIFY offsets/resolution with --probe.
    axis("TOUCH1_X", 0, 1919);
    axis("TOUCH1_Y", 0, 942);
    axis("TOUCH2_X", 0, 1919);
    axis("TOUCH2_Y", 0, 942);

    // Battery
    axis("BATTERY_LEVEL", 0, 100);
    btn("BATTERY_CHARGING");
};

///////////////////////////////////////////////////////////////////////////////
// setup() Called once by the engine right after the device opens (IS_BT is
// already set by then). USB streams the full report 0x01 immediately, so this is
// a no-op on USB. Over Bluetooth the DS4 only sends a cut-down report 0x01 until
// the host READS a calibration feature report — doing so flips it into the full
// 0x11 stream (motion + touchpad). Firmwares/stacks expose that feature as 0x02
// (USB-style, 37 B) or 0x05 (BT-style, 41 B); we read both and a missing one is
// logged + ignored. (If --probe over BT still shows no motion/touch, this read is
// being refused — likely the shared-mode open; that's the thing to chase next.)
void() setup =
{
    if (!IS_BT) { return; }

    // NOTE: the basic report 0x01 (sticks+buttons) auto-streams on connect with
    // NO setup (confirmed by Steam BT capture). The steps below UPGRADE to the
    // full report 0x11 (adds motion + touchpad); they are not needed for basic
    // input. Effective where we can actually read the pad (Linux/pi), not Windows.

    // 1) Reading the calibration feature flips the pad to full-report mode
    //    (0x02 USB-style / 0x05 BT-style). A missing one is logged + ignored.
    read_feature(0x02, 37);
    read_feature(0x05, 41);

    // 2) Send a host OUTPUT report 0x11 (sets the lightbar + confirms host
    //    presence). Lightbar dim blue so it's visually confirmable. The engine has
    //    already sized FeedbackBuf to BT_FEEDBACK_LEN (78) before setup() runs;
    //    the CRC lands in the last 4 bytes.
    // Header bytes confirmed against ndeadly/MissionControl dualshock4_controller
    // (a Bluetooth-host sysmodule, so authoritative for the BT wire format):
    //   [1]=0xC0|rate  [2]=0x20  [3]=0xF3  [4]=0x04  then motors/RGB.
    set_feedback_byte(0, 0x11);
    set_feedback_byte(1, 0xC0);  // 0xC0 | report-rate
    set_feedback_byte(2, 0x20);
    set_feedback_byte(3, 0xF3);  // feature enable flags (rumble + lightbar + ...)
    set_feedback_byte(4, 0x04);
    set_feedback_byte(8, 0x00);  // lightbar R
    set_feedback_byte(9, 0x00);  // lightbar G
    set_feedback_byte(10, 0x40); // lightbar B — dim blue == "phidimus woke me"
    feedback_crc32_sony_bt();
    send_feedback_buf();
};

///////////////////////////////////////////////////////////////////////////////
// parse() Called on every input report.
//
// IS_BT=0 (USB):  raw[0]=0x01, control data starts at raw[1].
// IS_BT=1 (BT):   raw[0]=0x11, control data starts at raw[3] (offset +2 vs USB).
//
// USB offsets (add the +2 BT shift via `o`):
//   [1..4]  LX LY RX RY            [5] dpad+face   [6] shoulders/system
//   [7]     PS/touchpad+counter    [8] L2 analog   [9] R2 analog
//   [13..18] gyro  [19..24] accel  [30] battery    [35..] touch

void(bytes raw) parse =
{
    // Transport + report-type handling:
    //   USB        -> report 0x01, control data at +0, full (motion + touch)
    //   BT full    -> report 0x11, control data at +2, full
    //   BT simple  -> report 0x01, control data at +0, NO motion/touch
    // setup() reads feature 0x02 over BT to switch the pad into full 0x11 mode;
    // until/unless that takes, we still decode the simple report so the sticks
    // and buttons work rather than nothing.
    local int o = 0;
    local int full = 1;
    if (IS_BT) {
        if (raw[0] == 0x11) {
            o = 2;
        } else {
            if (raw[0] != 0x01) { return; }
            full = 0;   // cut-down BT report: sticks / buttons / triggers only
        }
    }

    // Sticks and triggers
    set_axis("LEFT_STICK_X",  raw[1 + o]);
    set_axis("LEFT_STICK_Y",  raw[2 + o]);
    set_axis("RIGHT_STICK_X", raw[3 + o]);
    set_axis("RIGHT_STICK_Y", raw[4 + o]);
    set_axis("L2_ANALOG",     raw[8 + o]);
    set_axis("R2_ANALOG",     raw[9 + o]);

    // D-pad: low nibble of byte 5+o (0=N 1=NE 2=E 3=SE 4=S 5=SW 6=W 7=NW 8=neutral)
    local int dpad = raw[5 + o] & 0x0F;
    set_btn("BTN_DPAD_UP",    dpad == 0 || dpad == 1 || dpad == 7);
    set_btn("BTN_DPAD_RIGHT", dpad == 1 || dpad == 2 || dpad == 3);
    set_btn("BTN_DPAD_DOWN",  dpad == 3 || dpad == 4 || dpad == 5);
    set_btn("BTN_DPAD_LEFT",  dpad == 5 || dpad == 6 || dpad == 7);

    // Face buttons: high nibble of byte 5+o
    set_btn("BTN_SQUARE",   raw[5 + o] & 0x10);
    set_btn("BTN_CROSS",    raw[5 + o] & 0x20);
    set_btn("BTN_CIRCLE",   raw[5 + o] & 0x40);
    set_btn("BTN_TRIANGLE", raw[5 + o] & 0x80);

    // Shoulders + share/options + stick clicks: byte 6+o
    set_btn("BTN_L1",      raw[6 + o] & 0x01);
    set_btn("BTN_R1",      raw[6 + o] & 0x02);
    set_btn("BTN_L2",      raw[6 + o] & 0x04);
    set_btn("BTN_R2",      raw[6 + o] & 0x08);
    set_btn("BTN_SHARE",   raw[6 + o] & 0x10);
    set_btn("BTN_OPTIONS", raw[6 + o] & 0x20);
    set_btn("BTN_L3",      raw[6 + o] & 0x40);
    set_btn("BTN_R3",      raw[6 + o] & 0x80);

    // PS button + touchpad click: byte 7+o (upper 6 bits = report counter)
    set_btn("BTN_PS",       raw[7 + o] & 0x01);
    set_btn("BTN_TOUCHPAD", raw[7 + o] & 0x02);

    // Everything below lives only in the FULL report (USB 0x01 / BT 0x11), not
    // the cut-down BT 0x01. Bail before reading past a short report.
    if (!full) { return; }

    // IMU: gyro at 13..18, accel at 19..24 (USB; BT shifts +2 via o).
    // VERIFY order/sign/scale with --probe against a real pad before trusting.
    set_axis("GYRO_X",  s16le(raw[13 + o], raw[14 + o]));
    set_axis("GYRO_Y",  s16le(raw[15 + o], raw[16 + o]));
    set_axis("GYRO_Z",  s16le(raw[17 + o], raw[18 + o]));
    set_axis("ACCEL_X", s16le(raw[19 + o], raw[20 + o]));
    set_axis("ACCEL_Y", s16le(raw[21 + o], raw[22 + o]));
    set_axis("ACCEL_Z", s16le(raw[23 + o], raw[24 + o]));

    // Battery: byte 30+o. Low nibble = level; on DS4 the range/charging bit varies
    // by firmware (0-10 on battery, bit 4 = USB plugged). VERIFY with --probe.
    local int batt = raw[30 + o];
    set_axis("BATTERY_LEVEL",   (batt & 0x0F) * 10);
    set_btn("BATTERY_CHARGING",  batt & 0x10);

    // Touchpad: DS4 touch block begins ~byte 35+o. Finger 1 at 35..38:
    //   [35+o] = touch id + active flag (bit 7 = NOT touching)
    //   [36+o] = X low 8 bits
    //   [37+o] = X high 4 bits (low nibble) | Y low 4 bits (high nibble)
    //   [38+o] = Y high 8 bits
    // VERIFY the whole touch block with --probe — DS4 touch packing is fiddly.
    local int t1_0 = raw[35 + o];
    local int t1_x = raw[36 + o] | ((raw[37 + o] & 0x0F) << 8);
    local int t1_y = (raw[37 + o] >> 4) | (raw[38 + o] << 4);
    if (t1_0 & 0x80) {
        set_axis("TOUCH1_X", 960);
        set_axis("TOUCH1_Y", 471);
    } else {
        set_axis("TOUCH1_X", t1_x);
        set_axis("TOUCH1_Y", t1_y);
    }

    // Touchpad finger 2: bytes 39..42
    local int t2_0 = raw[39 + o];
    local int t2_x = raw[40 + o] | ((raw[41 + o] & 0x0F) << 8);
    local int t2_y = (raw[41 + o] >> 4) | (raw[42 + o] << 4);
    if (t2_0 & 0x80) {
        set_axis("TOUCH2_X", 960);
        set_axis("TOUCH2_Y", 471);
    } else {
        set_axis("TOUCH2_X", t2_x);
        set_axis("TOUCH2_Y", t2_y);
    }
};

///////////////////////////////////////////////////////////////////////////////
// write_feedback() Send lightbar + rumble to the controller.
//
// USB output report 0x05 (32 bytes):
//   [0] = 0x05 (report id)
//   [1] = enable flags: 0x01 rumble, 0x02 lightbar colour, 0x04 lightbar flash.
//         We set 0x07 (all three). Some firmwares want the 0xF0 high bits too;
//         VERIFY against a capture of the real PS4 driving the pad if it ignores us.
//   [2] = 0x00  (reserved)
//   [3] = 0x00  (reserved)
//   [4] = motor_right (RUMBLE_SOFT, high-frequency)
//   [5] = motor_left  (RUMBLE_HEAVY, low-frequency)
//   [6] = lightbar_red   [7] = lightbar_green   [8] = lightbar_blue
//   [9] = flash_on   [10] = flash_off
//
// BT output report 0x11 (78 bytes, zero-padded to 547 by engine):
//   [0] = 0x11 (report id)   [1] = 0xC0 (HID flags / poll)   [2] = 0xA0 (?)
//   [3] = enable flags (0x07)   [4] = 0x00   [5] = 0x00
//   [6] = motor_right   [7] = motor_left
//   [8] = red   [9] = green   [10] = blue   [11] = flash_on   [12] = flash_off
//   [74..77] = CRC32 (feedback_crc32_sony_bt)
// The BT header bytes [1]/[2] and the CRC framing need confirming against a real
// DS4 BT capture — treated as a best-effort first pass.

void() write_feedback =
{
    local int motor_r = get_feedback("RUMBLE_SOFT");
    local int motor_l = get_feedback("RUMBLE_HEAVY");
    local int led_r = get_feedback("LED_R");
    local int led_g = get_feedback("LED_G");
    local int led_b = get_feedback("LED_B");
    local int fl_on  = get_feedback("LED_FLASH_ON");
    local int fl_off = get_feedback("LED_FLASH_OFF");

    if (IS_BT) {
        // Header bytes per ndeadly/MissionControl dualshock4_controller (BT-host,
        // authoritative): [1]=0xC0|rate [2]=0x20 [3]=0xF3 [4]=0x04.
        set_feedback_byte(0, 0x11);
        set_feedback_byte(1, 0xC0);
        set_feedback_byte(2, 0x20);
        set_feedback_byte(3, 0xF3);
        set_feedback_byte(4, 0x04);
        set_feedback_byte(6, motor_r);
        set_feedback_byte(7, motor_l);
        set_feedback_byte(8, led_r);
        set_feedback_byte(9, led_g);
        set_feedback_byte(10, led_b);
        set_feedback_byte(11, fl_on);
        set_feedback_byte(12, fl_off);
        feedback_crc32_sony_bt();
    } else {
        set_feedback_byte(0, 0x05);
        set_feedback_byte(1, 0x07);
        set_feedback_byte(4, motor_r);
        set_feedback_byte(5, motor_l);
        set_feedback_byte(6, led_r);
        set_feedback_byte(7, led_g);
        set_feedback_byte(8, led_b);
        set_feedback_byte(9, fl_on);
        set_feedback_byte(10, fl_off);
    }
};
