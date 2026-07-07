// Xbox 360 Wired Controller — usb_device output module (Engine 4.0).
//
// Presents a real Microsoft Xbox 360 controller over USB/IP. The OS binds its
// own driver (xusb22.sys on Windows, xpad on Linux), so we ARE an XInput pad —
// no kernel driver of our own. This is the workhorse output: most things that
// read a controller read an Xbox 360 pad.
//
// Signal names and button masks follow the XInput XUSB_GAMEPAD_* convention, so
// configs map to familiar names (XINPUT_GAMEPAD_A, LEFT_STICK_X, ...).
//
// The 360 is a VENDOR-class device (FF/5D/01), not HID — there is no HID report
// descriptor. Input reports go out EP 0x81 (20 bytes); the host sends rumble and
// LED-ring commands in on EP 0x01, decoded in on_output().
//
// REAL-CONSOLE AUTH (XSM3) — OPT-IN, disabled by default. A real Xbox 360 console
// (unlike Windows' xusb22.sys) demands the XSM3 challenge/response or it drops the pad
// in ~10 s. Uncomment the import below to overlay the XSM3 handshake: it OVERRIDES
// declare_usb() with the security-capable descriptor and ADDS on_control() (everything
// else here stays the same). It ships commented out because it is still a WIP capture
// scaffold — enabling it changes the PC-proven descriptor and is only for bench-testing
// against a real console. Comment it back out to return to the plain, proven pad.
// import "handshakes/xsm3.qc"

string MODULE_ID      = "xbox360_usb";
string MODULE_NAME    = "Xbox 360 Controller (virtual USB)";
string MODULE_VERSION = "2.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.0.0";
string DRIVER         = "usb_device";

// USB identity. A genuine wired Xbox 360 controller.
// ish, we have a custom name and sn so we know its us.
int    USB_VID          = 0x045E;
int    USB_PID          = 0x028E;
int    USB_BCD_DEVICE   = 0x0114;
int    USB_CLASS        = 0xFF;   // vendor specific
int    USB_SUBCLASS     = 0xFF;
int    USB_PROTOCOL     = 0xFF;
int    USB_EP0_SIZE     = 0x08;   // the real controller uses an 8-byte EP0
string USB_MANUFACTURER = "Microsoft";
string USB_PRODUCT      = "Phidimus Controller";
string USB_SERIAL       = "PHIDIMUS360";

void() declare_usb =
{
    // Single interface 0 (class FF / subclass 5D / protocol 01) with the
    // vendor-specific 0x21 descriptor xusb22.sys looks for
    // plus the two interrupt endpoints. wTotalLength = 9+9+17+7+7 = 0x31.
    usb_config(
        "09 02 31 00 01 01 00 A0 FA"               // configuration
        "09 04 00 00 02 FF 5D 01 00"               // interface 0
        "11 21 00 01 01 25 81 14 00 00 00 00 13 01 08 00 00" // vendor 0x21 desc
        "07 05 81 03 20 00 04"                     // EP 0x81 IN,  interrupt, 4 ms
        "07 05 01 03 20 00 08"                     // EP 0x01 OUT, interrupt, 8 ms
    );

    in_endpoint(0x81);   // pack() reports go here
    out_endpoint(0x01);  // host rumble / LED arrive here -> on_output()
};

void() declare_signals =
{
    report_len(20);   // XUSB input report: 2 header + 2 buttons + 2 triggers + 8 sticks + 6 pad

    // Rumble motors the game drives; routed back to the input device via
    // [xbox360_usb.feedback] in the config.
    out_feedback("RUMBLE_LARGE", 0, 255);  // left / low-frequency  motor
    out_feedback("RUMBLE_SMALL", 0, 255);  // right / high-frequency motor
    out_feedback("LED_PATTERN",  0, 13);   // LED ring animation id the game requests

    // wButtons bitmask — matches the XInput XUSB_GAMEPAD_* constants exactly,
    // so byte 2 = btns&0xFF and byte 3 = btns>>8 pack directly.
    out_btn("XINPUT_GAMEPAD_DPAD_UP",        0x0001);
    out_btn("XINPUT_GAMEPAD_DPAD_DOWN",      0x0002);
    out_btn("XINPUT_GAMEPAD_DPAD_LEFT",      0x0004);
    out_btn("XINPUT_GAMEPAD_DPAD_RIGHT",     0x0008);
    out_btn("XINPUT_GAMEPAD_START",          0x0010);
    out_btn("XINPUT_GAMEPAD_BACK",           0x0020);
    out_btn("XINPUT_GAMEPAD_LEFT_THUMB",     0x0040);
    out_btn("XINPUT_GAMEPAD_RIGHT_THUMB",    0x0080);
    out_btn("XINPUT_GAMEPAD_LEFT_SHOULDER",  0x0100);
    out_btn("XINPUT_GAMEPAD_RIGHT_SHOULDER", 0x0200);
    out_btn("XINPUT_GAMEPAD_GUIDE",          0x0400);
    out_btn("XINPUT_GAMEPAD_A",              0x1000);
    out_btn("XINPUT_GAMEPAD_B",              0x2000);
    out_btn("XINPUT_GAMEPAD_X",              0x4000);
    out_btn("XINPUT_GAMEPAD_Y",              0x8000);

    out_axis("LEFT_STICK_X",  -32768, 32767);
    out_axis("LEFT_STICK_Y",  -32768, 32767);
    out_axis("RIGHT_STICK_X", -32768, 32767);
    out_axis("RIGHT_STICK_Y", -32768, 32767);
    out_axis("LEFT_TRIGGER",  0, 255);
    out_axis("RIGHT_TRIGGER", 0, 255);
};

void() pack =
{
    set_report_byte(0, 0x00);  // message type
    set_report_byte(1, 0x14);  // length = 20

    local int btns = get_buttons();
    set_report_byte(2, btns & 0xFF);
    set_report_byte(3, (btns >> 8) & 0xFF);

    set_report_byte(4, get_axis("LEFT_TRIGGER")  & 0xFF);
    set_report_byte(5, get_axis("RIGHT_TRIGGER") & 0xFF);

    set_report_word(6,  get_axis("LEFT_STICK_X"));
    set_report_word(8,  get_axis("LEFT_STICK_Y"));
    set_report_word(10, get_axis("RIGHT_STICK_X"));
    set_report_word(12, get_axis("RIGHT_STICK_Y"));
    // Bytes 14-19: reserved (zeroed each frame).
};

// Host -> device on EP 0x01. The Xbox 360 protocol uses the first byte as the
// command id: 0x00 = rumble, 0x01 = LED-ring pattern.
void(bytes raw) on_output =
{
    if (raw[0] == 0x00) {
        // [2]=0x00 [3]=left motor [4]=right motor
        set_out_feedback("RUMBLE_LARGE", raw[3]);
        set_out_feedback("RUMBLE_SMALL", raw[4]);
    }
    if (raw[0] == 0x01) {
        // [2] = LED ring pattern (0-13)
        set_out_feedback("LED_PATTERN", raw[2]);
    }
};
