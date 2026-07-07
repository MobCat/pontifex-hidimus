// PlayStation 5 DualSense. Monolithic input module for phidimus.
// Handles both USB (report 0x01) and Bluetooth (report 0x31) from one module.

// The engine detects which transport is connected after Open() and sets IS_BT:
//   IS_BT = 0  ->  USB path     (64-byte output report 0x02)
//   IS_BT = 1  ->  Bluetooth    (78-byte output report 0x31, zero-padded to 547)

// USB vs BT byte layout differences
// BT input report 0x31 wraps the same control data as USB report 0x01 with one
// extra byte at raw[1] (BT sequence counter). All field offsets shift by +1:
//   USB raw[n]  →  BT raw[n+1]   for all sticks, buttons, battery, touchpad

// BT output report 0x31 prepends two header bytes (seq_tag, Sony tag 0x10) and
// appends a CRC32. All USB output byte offsets shift by +2 for BT.

string MODULE_ID      = "ps5ds";
string MODULE_NAME    = "PlayStation 5 DualSense";
string MODULE_VERSION = "2.7.2";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.5.0";
int    VID            = 0x054C;
int    PID            = 0x0CE6;
string DRIVER         = "hid_input";
// No TRANSPORT. Driver opens whichever connection type is available (USB preferred).
// IS_BT is set to 1 by the engine after Open() when Bluetooth is detected.
int IS_BT = 0;
// BT_FEEDBACK_LEN: engine resizes FeedbackBuf from 64→78 when BT is detected.
int BT_FEEDBACK_LEN = 78;
// OUTPUT_REPORT_LEN_BT: engine zero pads the 78-byte BT report to 547 for WriteFile.
// (BT HID descriptor max = 547; Windows requires the buffer to be exactly this size.)
int OUTPUT_REPORT_LEN_BT = 547;

// STALL_TIMEOUT_MS: the DualSense streams continuously (IMU packets even when
// idle), so going silent this long means the link dropped — pad switched off,
// out of range, or handed Bluetooth over to a freshly-plugged USB cable. The
// engine then reconnects and re-selects the best transport (USB preferred).
// Safe here precisely because the pad always streams; do NOT set it on pads that
// only report on input change.
int STALL_TIMEOUT_MS = 2000;

// s16le combines two little-endian bytes into a signed 16-bit value.
// Used for the IMU (gyro/accel) which report raw signed int16.
int(int lo, int hi) s16le =
{
    local int v = lo | (hi << 8);
    if (v >= 32768) { v = v - 65536; }
    return v;
};

void() declare_signals =
{
    // Feedback buffer size. Engine grows this to BT_FEEDBACK_LEN on BT connect.
    feedback_len(64);

    // Feedback signals (output to the controller) — same names over USB and BT.
    feedback("RUMBLE_HEAVY", 0, 255);
    feedback("RUMBLE_SOFT",  0, 255);
    feedback("LED_R", 0, 255);
    feedback("LED_G", 0, 255);
    feedback("LED_B", 0, 255);
    feedback("MIC_LED", 0, 2);         // 0=off  1=on  2=pulse

    // Player indicator LEDs — the 5 dots between touchpad and lightbar.
    // The firmware enforces mirroring (confirmed by raw byte test 2026-06-12):
    // bitmask 0x01 and 0x10 both light the OUTER pair, 0x02 lights the INNER
    // pair, 0x04 the centre. Individual dots cannot be addressed, so these
    // three pair signals are the full hardware capability.
    feedback("LED_P_OUTER",  0, 1);
    feedback("LED_P_INNER",  0, 1);
    feedback("LED_P_CENTRE", 0, 1);
    feedback("LED_P_BRIGHTNESS", 0, 2); // all player dots share one brightness: 0=high 1=medium 2=low

    // valid_flag0: which output features to apply this frame (bit 0 rumble,
    // bit 2 right trigger, bit 3 left trigger). Driven by the config / passed
    // through from a game for a USB-DualSense passthrough; defaults to rumble.
    feedback("FEATURE_FLAGS", 0, 255);
    // Adaptive-trigger effect blocks (1 mode + 10 params each), passed through.
    feedback_blob("TRIGGER_RIGHT", 11);
    feedback_blob("TRIGGER_LEFT",  11);

    // Adaptive-trigger STRENGTH scalars (0-255) — the "fake FFB" path. A config can
    // drive these from a live value (e.g. a console's force feedback via a
    // [<output>.feedback] map); write_feedback() turns the strength into a uniform
    // RESISTANCE trigger effect blob at the same offset the raw TRIGGER_* passthrough
    // uses. Left at 0 (undriven) they do nothing, so raw-blob passthrough configs are
    // unaffected. See config/xbox/ps5_to_ogxbox_racingwheel.ini.
    feedback("TRIGGER_R_STRENGTH", 0, 255);
    feedback("TRIGGER_L_STRENGTH", 0, 255);

    // Digital buttons
    btn("BTN_CROSS");
    btn("BTN_CIRCLE");
    btn("BTN_SQUARE");
    btn("BTN_TRIANGLE");
    btn("BTN_L1");
    btn("BTN_R1");
    btn("BTN_L2");
    btn("BTN_R2");
    btn("BTN_CREATE");
    btn("BTN_OPTIONS");
    btn("BTN_L3");
    btn("BTN_R3");
    btn("BTN_PS");
    btn("BTN_TOUCHPAD");
    btn("BTN_MUTE");
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

    // IMU — gyroscope (angular velocity) and accelerometer, raw signed int16.
    // Map GYRO_* to a virtual stick or mouse for motion aim on controllers that
    // lack it (e.g. gyro-to-mouse, or gyro → Xbox right stick).
    axis("GYRO_X",  -32768, 32767);
    axis("GYRO_Y",  -32768, 32767);
    axis("GYRO_Z",  -32768, 32767);
    axis("ACCEL_X", -32768, 32767);
    axis("ACCEL_Y", -32768, 32767);
    axis("ACCEL_Z", -32768, 32767);

    // Touchpad
    axis("TOUCH1_X", 0, 1919);
    axis("TOUCH1_Y", 0, 1079);
    axis("TOUCH2_X", 0, 1919);
    axis("TOUCH2_Y", 0, 1079);

    // Battery
    axis("BATTERY_LEVEL", 0, 100);
    btn("BATTERY_CHARGING");

    // Calibration feature reports (same IDs over USB and BT. No offset shift).
    calib_field_ro("Controller BT MAC",
        "The controller's own Bluetooth address. Used to identify the device when pairing.",
        0x22, 1, 6);
    calib_field("Paired Host MAC",
        "Bluetooth MAC of the paired host (bytes 1-6). Write your PC's BT MAC to re-pair over USB.",
        0x20, 1, 6);
    calib_field_ro("Firmware Version",
        "Controller firmware build date and version string.",
        0x09, 1, 63);
    calib_field_ro("Device Info",
        "Hardware revision, firmware version (numeric), and serial number.",
        0x0B, 1, 63);
    calib_field("IMU Calibration",
        "Gyroscope bias/sensitivity and accelerometer range. Modify only after PCB sensor replacement.",
        0x05, 1, 26);
};

///////////////////////////////////////////////////////////////////////////////
// setup() Device-init handshake, run once on Open() (and on every reconnect).
//
// Over Bluetooth the DualSense boots in a REDUCED report mode (report 0x01:
// buttons + sticks only — no IMU, touch, or full feedback) and only switches to
// the full 0x31 report once the host READS feature report 0x05 (the calibration
// report). Reading it here is the exact unlock the Linux hid-playstation driver
// performs on probe.
//
// Doing it ourselves means phidimus owns the link end to end and does NOT depend
// on hid-playstation being bound — which matters because that driver also seizes
// the OUTPUT channel (LEDs via /sys/class/leds, rumble via force-feedback) and
// overrides our 0x31 output writes. With our own unlock in place, hid-playstation
// can be blacklisted on the dongle so feedback (rumble/haptics/LEDs) reaches the
// pad. See docs/DualSense.md.
//
// USB needs no unlock — report 0x01 already carries the full payload.
void() setup =
{
    if (!IS_BT) { return; }
    read_feature(0x05, 41);   // DS_FEATURE_REPORT_CALIBRATION — enables full 0x31 BT reports
};

///////////////////////////////////////////////////////////////////////////////
// parse() Called on every input report.
//
// IS_BT=0 (USB):  raw[0]=0x01  sticks at [1:6]   buttons at [8:10]  batt at [53]  touch at [33:40]
// IS_BT=1 (BT):   raw[0]=0x31  sticks at [2:7]   buttons at [9:11]  batt at [54]  touch at [34:41]
//
// All field offsets in the BT report are exactly +1 relative to USB.

void(bytes raw) parse =
{
    // BT: only decode report 0x31.
    if (IS_BT) {
        if (raw[0] != 0x31) { return; }
    }

    local int o = IS_BT;   // byte offset: 0 for USB, 1 for BT

    // Sticks and triggers
    set_axis("LEFT_STICK_X",  raw[1 + o]);
    set_axis("LEFT_STICK_Y",  raw[2 + o]);
    set_axis("RIGHT_STICK_X", raw[3 + o]);
    set_axis("RIGHT_STICK_Y", raw[4 + o]);
    set_axis("L2_ANALOG",     raw[5 + o]);
    set_axis("R2_ANALOG",     raw[6 + o]);

    // D-pad: low nibble of byte 8+o  (0=N 1=NE 2=E 3=SE 4=S 5=SW 6=W 7=NW 8=neutral)
    local int dpad = raw[8 + o] & 0x0F;
    set_btn("BTN_DPAD_UP",    dpad == 0 || dpad == 1 || dpad == 7);
    set_btn("BTN_DPAD_RIGHT", dpad == 1 || dpad == 2 || dpad == 3);
    set_btn("BTN_DPAD_DOWN",  dpad == 3 || dpad == 4 || dpad == 5);
    set_btn("BTN_DPAD_LEFT",  dpad == 5 || dpad == 6 || dpad == 7);

    // Face buttons: high nibble of byte 8+o
    set_btn("BTN_SQUARE",   raw[8 + o] & 0x10);
    set_btn("BTN_CROSS",    raw[8 + o] & 0x20);
    set_btn("BTN_CIRCLE",   raw[8 + o] & 0x40);
    set_btn("BTN_TRIANGLE", raw[8 + o] & 0x80);

    // Shoulder buttons + system: byte 9+o
    set_btn("BTN_L1",      raw[9 + o] & 0x01);
    set_btn("BTN_R1",      raw[9 + o] & 0x02);
    set_btn("BTN_L2",      raw[9 + o] & 0x04);
    set_btn("BTN_R2",      raw[9 + o] & 0x08);
    set_btn("BTN_CREATE",  raw[9 + o] & 0x10);
    set_btn("BTN_OPTIONS", raw[9 + o] & 0x20);
    set_btn("BTN_L3",      raw[9 + o] & 0x40);
    set_btn("BTN_R3",      raw[9 + o] & 0x80);

    // PS / touchpad / mute: byte 10+o
    set_btn("BTN_PS",       raw[10 + o] & 0x01);
    set_btn("BTN_TOUCHPAD", raw[10 + o] & 0x02);
    set_btn("BTN_MUTE",     raw[10 + o] & 0x04);

    // IMU: gyro at bytes 16-21, accel at 22-27 (USB; BT shifts +1 via o).
    // Each axis is a little-endian signed int16. Offsets per the DualSense
    // report layout — verify direction/scale with --probe and tune if needed.
    set_axis("GYRO_X",  s16le(raw[16 + o], raw[17 + o]));
    set_axis("GYRO_Y",  s16le(raw[18 + o], raw[19 + o]));
    set_axis("GYRO_Z",  s16le(raw[20 + o], raw[21 + o]));
    set_axis("ACCEL_X", s16le(raw[22 + o], raw[23 + o]));
    set_axis("ACCEL_Y", s16le(raw[24 + o], raw[25 + o]));
    set_axis("ACCEL_Z", s16le(raw[26 + o], raw[27 + o]));

    // Battery: byte 53+o  (bits 3:0 = level 0-10, bit 4 = charging/plugged-in)
    local int batt = raw[53 + o];
    set_axis("BATTERY_LEVEL",   (batt & 0x0F) * 10);
    set_btn("BATTERY_CHARGING",  batt & 0x10);

    // Touchpad finger 1: bytes 33+o .. 36+o
    // Byte 33+o bit 7 = inactive (0=touching, 1=not touching)
    // X = 12 bits across bytes 34+o & 35+o low nibble
    // Y = 12 bits across bytes 35+o high nibble & 36+o
    local int t1_0 = raw[33 + o];
    local int t1_1 = raw[34 + o];
    local int t1_2 = raw[35 + o];
    local int touch1_x = t1_1 | ((t1_2 & 0x0F) << 8);
    local int touch1_y = (t1_2 >> 4) | (raw[36 + o] << 4);
    if (t1_0 & 0x80) {
        set_axis("TOUCH1_X", 960);
        set_axis("TOUCH1_Y", 540);
    } else {
        set_axis("TOUCH1_X", touch1_x);
        set_axis("TOUCH1_Y", touch1_y);
    }

    // Touchpad finger 2: bytes 37+o .. 40+o
    local int t2_0 = raw[37 + o];
    local int t2_1 = raw[38 + o];
    local int t2_2 = raw[39 + o];
    local int touch2_x = t2_1 | ((t2_2 & 0x0F) << 8);
    local int touch2_y = (t2_2 >> 4) | (raw[40 + o] << 4);
    if (t2_0 & 0x80) {
        set_axis("TOUCH2_X", 960);
        set_axis("TOUCH2_Y", 540);
    } else {
        set_axis("TOUCH2_X", touch2_x);
        set_axis("TOUCH2_Y", touch2_y);
    }
};

///////////////////////////////////////////////////////////////////////////////
// write_feedback() Send LED + rumble to the controller.

// USB output report 0x02 (64 bytes):
//   [0]  = 0x02 (report ID)
//   [1]  = valid_flag0 = 0x03  (COMPATIBLE_VIBRATION | HAPTICS_SELECT)
//   [2]  = valid_flag1 = 0x15  (MIC_MUTE_LED | LIGHTBAR | PLAYER_INDICATOR)
//   [3]  = motor_right (RUMBLE_SOFT)
//   [4]  = motor_left  (RUMBLE_HEAVY)
//   [9]  = mute_button_led (MIC_LED)
//   [43] = led_brightness (LED_P_BRIGHTNESS: 0=high 1=medium 2=low)
//   [44] = player_leds bitmask
//   [45] = lightbar_red
//   [46] = lightbar_green
//   [47] = lightbar_blue
//
// BT output report 0x31 (78 bytes, zero-padded to 547 by engine):
//   [0]  = 0x31 (report ID)
//   [1]  = seq_tag = (next_counter() << 4) | 0x00
//   [2]  = 0x10   (Sony BT tag — tells firmware the common block starts at [3])
//   [3]  = valid_flag0 = 0x03  (COMPATIBLE_VIBRATION | HAPTICS_SELECT)
//   [4]  = valid_flag1 = 0x15  (MIC_MUTE_LED | LIGHTBAR | PLAYER_INDICATOR)
//          Same bit layout as USB: bit 4 = PLAYER_INDICATOR, bit 3 = RELEASE_LEDS.
//          (Confirmed via BT packet capture 2026-06: host sends 0x55 and player LEDs respond;
//          the old theory that BT swapped bits 3/4 was wrong.)
//   [5]  = motor_right (RUMBLE_SOFT)
//   [6]  = motor_left  (RUMBLE_HEAVY)
//   [11] = mute_button_led (MIC_LED)
//   [41] = valid_flag2 = 0x03  (bit 1 = LIGHTBAR_SETUP_CONTROL_ENABLE — required to apply [44];
//          bit 0 unknown but always set by captured hosts. Was wrongly written at [43],
//          a reserved byte, so LIGHT_OUT never applied and the firmware kept the lightbar.)
//   [44] = lightbar_setup = 0x02 (LIGHT_OUT — switch lightbar from firmware to host control)
//   [45] = led_brightness (LED_P_BRIGHTNESS: 0=high 1=medium 2=low)
//   [46] = player_leds bitmask
//   [47] = lightbar_red
//   [48] = lightbar_green
//   [49] = lightbar_blue
//   [74:77] = CRC32 (written by feedback_crc32_sony_bt())
//
// Offsets verified against BT captures of a working Windows host (ps5BT.pcapng,
// ps5 player led.pcapng). Note: that host omits the 0x10 tag at [2] and packs the
// common block one byte earlier — the firmware accepts both layouts; we keep the
// tagged Sony layout, so all common-block offsets here are capture offsets +1.

// trigger_resistance builds a UNIFORM adaptive-trigger resistance effect into the output
// report at byte `off`, force `strength` (0-255) — the "fake FFB" turned into trigger feel.
//
// A DualSense resistance is NOT [mode, start, force]; it's a 10-ZONE effect:
//   [0]    effect type 0x01 (resistance)
//   [1..2] "active zones" bitmask, one bit per zone (10 zones -> 0x03FF)
//   [3..6] a 3-bit force (0-7) packed per zone, little-endian
//   [7..10] unused (0)
// For a uniform pull we mark all 10 zones active (FF 03) and write the same 3-bit force
// into every zone. 0x09249249 has one set bit at the base of each 3-bit zone field, so
// multiplying it by v (<=7, no carry between fields) writes v into all ten zones at once.
// (Uniform fill is symmetric, so the exact per-zone bit order doesn't matter here.)
//
// The controller only APPLIES this when valid_flag0's trigger bit is set (see
// write_feedback). strength 0 leaves the blit'd blob untouched (trigger free). Format
// ref: Nielk1/TriggerEffectGenerator. Effect type 0x21 is HARDWARE-CONFIRMED on our
// DualSense (the older 0x01 "simple resistance" type did NOT take — see DualSense.md).
void(int off, int strength) trigger_resistance =
{
    if (strength <= 0) { return; }
    local int v   = strength * 7 / 255;    // 0-255 force -> 0-7 per-zone amplitude
    local int amp = 0x09249249 * v;        // v written into all ten 3-bit zone fields
    set_feedback_byte(off + 0, 0x21);      // effect type: resistance (0x21 confirmed on hw)
    set_feedback_byte(off + 1, 0xFF);      // active zones 0-7
    set_feedback_byte(off + 2, 0x03);      // active zones 8-9
    set_feedback_byte(off + 3, amp & 0xFF);
    set_feedback_byte(off + 4, (amp >> 8) & 0xFF);
    set_feedback_byte(off + 5, (amp >> 16) & 0xFF);
    set_feedback_byte(off + 6, (amp >> 24) & 0xFF);
    set_feedback_byte(off + 7, 0);
    set_feedback_byte(off + 8, 0);
    set_feedback_byte(off + 9, 0);
    set_feedback_byte(off + 10, 0);
};

void() write_feedback =
{
    local int led_r = get_feedback("LED_R");
    local int led_g = get_feedback("LED_G");
    local int led_b = get_feedback("LED_B");

    // valid_flag0 drives which features the controller applies. 0 (unset by the
    // config/game) falls back to rumble+haptics so basic feedback always works.
    local int vf0 = get_feedback("FEATURE_FLAGS");
    if (vf0 == 0) { vf0 = 0x03; }
    // Enable the adaptive-trigger FFB bits when a resistance strength is being driven
    // (valid_flag0 bit 2 = R2, bit 3 = L2). WITHOUT these the controller silently
    // ignores the trigger effect blob — which is why the "fake FFB" felt static. A raw
    // passthrough config drives FEATURE_FLAGS itself and these signals stay 0, so it's
    // unaffected.
    if (get_feedback("TRIGGER_R_STRENGTH") > 0) { vf0 = vf0 | 0x04; }
    if (get_feedback("TRIGGER_L_STRENGTH") > 0) { vf0 = vf0 | 0x08; }

    if (IS_BT) {
        set_feedback_byte(0, 0x31);
        set_feedback_byte(1, (next_counter() << 4) | 0x00);
        set_feedback_byte(2, 0x10);
        set_feedback_byte(3, vf0);
        set_feedback_byte(4, 0x15);
        set_feedback_byte(5, get_feedback("RUMBLE_SOFT"));
        set_feedback_byte(6, get_feedback("RUMBLE_HEAVY"));
        // Adaptive triggers: BT common block is USB+2, so right→[13], left→[24].
        blit_feedback_blob(13, "TRIGGER_RIGHT");
        blit_feedback_blob(24, "TRIGGER_LEFT");
        trigger_resistance(13, get_feedback("TRIGGER_R_STRENGTH"));
        trigger_resistance(24, get_feedback("TRIGGER_L_STRENGTH"));
        set_feedback_byte(11, get_feedback("MIC_LED"));
        set_feedback_byte(41, 0x03);
        set_feedback_byte(44, 0x02);
        set_feedback_byte(45, get_feedback("LED_P_BRIGHTNESS"));
        local int leds_bt = 0;
        if (get_feedback("LED_P_OUTER"))  { leds_bt = leds_bt | 0x11; }
        if (get_feedback("LED_P_INNER"))  { leds_bt = leds_bt | 0x0A; }
        if (get_feedback("LED_P_CENTRE")) { leds_bt = leds_bt | 0x04; }
        set_feedback_byte(46, leds_bt);
        set_feedback_byte(47, led_r);
        set_feedback_byte(48, led_g);
        set_feedback_byte(49, led_b);
        feedback_crc32_sony_bt();
    } else {
        set_feedback_byte(0, 0x02);
        set_feedback_byte(1, vf0);
        set_feedback_byte(2, 0x15);
        set_feedback_byte(3, get_feedback("RUMBLE_SOFT"));
        set_feedback_byte(4, get_feedback("RUMBLE_HEAVY"));
        // Adaptive triggers: USB output 0x02 right→[11], left→[22].
        blit_feedback_blob(11, "TRIGGER_RIGHT");
        blit_feedback_blob(22, "TRIGGER_LEFT");
        trigger_resistance(11, get_feedback("TRIGGER_R_STRENGTH"));
        trigger_resistance(22, get_feedback("TRIGGER_L_STRENGTH"));
        set_feedback_byte(9, get_feedback("MIC_LED"));
        set_feedback_byte(43, get_feedback("LED_P_BRIGHTNESS"));
        local int leds_usb = 0;
        if (get_feedback("LED_P_OUTER"))  { leds_usb = leds_usb | 0x11; }
        if (get_feedback("LED_P_INNER"))  { leds_usb = leds_usb | 0x0A; }
        if (get_feedback("LED_P_CENTRE")) { leds_usb = leds_usb | 0x04; }
        set_feedback_byte(44, leds_usb);
        set_feedback_byte(45, led_r);
        set_feedback_byte(46, led_g);
        set_feedback_byte(47, led_b);
    }
};

// power_off() — turn the controller off on clean exit (Ctrl+C), the way a PS5
// console powers the pad off when it shuts down. Bluetooth only: a wired pad is
// left running (it is USB-powered and the engine just unhides it on close).
//
// DualSense Bluetooth control feature report 0x08: byte[0]=0x08, byte[1]=0x02
// (power off), 47 bytes total with a SET_FEATURE CRC32 (seed 0x53) in the last
// four bytes. Reference: nowrep/dualsensectl command_power_off.
void() power_off =
{
    if (!IS_BT) { return; }            // wired connection: nothing to do
    feedback_len(47);                  // allocate + zero a 47-byte buffer
    set_feedback_byte(0, 0x08);        // DS_FEATURE_REPORT_BLUETOOTH_CONTROL
    set_feedback_byte(1, 0x02);        // DS_BLUETOOTH_CONTROL_OFF
    feedback_crc32_sony_bt(0x53);      // SET_FEATURE Bluetooth CRC (seed 0x53)
    write_feature_buf();               // HidD_SetFeature
};
