// Xbox Original Controller (Controller S) — usb_device output module.
//
// Presents a real original-Xbox controller (an XID device) over the engine's
// USB transport: USB/IP on the desktop bench, and the raw-gadget backend on
// phidimus-pi to drive a REAL original Xbox console through the mini-USB port.
// This is the top rung of the output test ladder and our first real-console
// output — the OG Xbox does no controller authentication, so a faithful XID
// device is accepted directly (no hub needed; the ogx360 precedent).
//
// Everything here was captured from a real Controller S (045E:0289) with
// `phidimus-sdk --usb` — device + config descriptors, the XID vendor
// descriptor, and the capability reports. "Capture reality, paste it."
//
// The XID is a VENDOR-class device (interface 58/42/00), not HID. Unlike the
// Xbox 360's 0x21 descriptor (which rides inside the config descriptor), the
// XID descriptor and capability reports are fetched by the console through
// VENDOR control requests on EP0 — answered here in on_control(). Input
// reports (20 bytes) go out EP 0x81; the console sends rumble in on EP 0x02,
// decoded in on_output().
//
// Signal names mirror modules/input/xboxog_winusb.qc exactly, so an OG-Xbox pad
// passthrough is 1:1 and any other input maps by the same familiar names.

string MODULE_ID      = "xboxog_rawusb";
string MODULE_NAME    = "Xbox Original Controller (virtual USB / XID)";
string MODULE_VERSION = "1.1.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.5.0";
string DRIVER         = "usb_device";

// USB identity — straight off a real Controller S (045E:0289). bDeviceClass is
// 00/00/00 (per-interface); no string descriptors on the real pad, so ours are
// empty too. bcdDevice 0x0121.
int    USB_VID          = 0x045E;
int    USB_PID          = 0x0289;
int    USB_BCD_DEVICE   = 0x0121;
int    USB_EP0_SIZE     = 0x08;
string USB_MANUFACTURER = "";
string USB_PRODUCT      = "";
string USB_SERIAL       = "";

void() declare_usb =
{
    // Configuration descriptor pasted verbatim from the real controller capture.
    // wTotalLength = 9+9+7+7 = 0x20. One vendor interface (58/42/00) + two
    // interrupt endpoints (both 32 B, 4 ms).
    usb_config(
        "09 02 20 00 01 01 00 80 32"   // configuration: 1 interface, bus-powered 100 mA
        "09 04 00 00 02 58 42 00 00"   // interface 0: class 58/42/00 (XID)
        "07 05 81 03 20 00 04"         // EP 0x81 IN,  interrupt, 32 B, 4 ms
        "07 05 02 03 20 00 04"         // EP 0x02 OUT, interrupt, 32 B, 4 ms
    );

    in_endpoint(0x81);    // pack() reports go out here
    out_endpoint(0x02);   // console rumble arrives here -> on_output()
};

void() declare_signals =
{
    report_len(20);   // XID input report: 2 header + 1 buttons + 1 pad + 6 analog btn + 2 trig + 8 stick

    // Rumble the console drives, routed back to the input device via
    // [xboxog_rawusb.feedback] in the config. Same two 16-bit actuators the input
    // module's write_feedback() emits (heavy/left, light/right).
    out_feedback("RUMBLE_LEFT",  0, 255);
    out_feedback("RUMBLE_RIGHT", 0, 255);

    // WHEELFEEDBACK: the console's force-feedback magnitude as a single 0-255 scalar
    // (the primary/left force byte). Named for the racing-wheel path — a game like
    // Colin McRae Rally 2005 streams a mono force here — but available to any config to
    // route onto, say, DualSense adaptive triggers as a "fake FFB" feel. On a plain
    // gamepad it just mirrors the left rumble level; nothing forces a config to use it.
    out_feedback("WHEELFEEDBACK", 0, 255);

    // Digital buttons — byte 2 bitmask (dpad + system + stick clicks only).
    // The face buttons are ANALOG on the OG Xbox (see below), not in this byte.
    out_btn("BTN_DPAD_UP",    0x01);
    out_btn("BTN_DPAD_DOWN",  0x02);
    out_btn("BTN_DPAD_LEFT",  0x04);
    out_btn("BTN_DPAD_RIGHT", 0x08);
    out_btn("BTN_START",      0x10);
    out_btn("BTN_BACK",       0x20);
    out_btn("BTN_L3",         0x40);   // left  stick click
    out_btn("BTN_R3",         0x80);   // right stick click

    // Analog face buttons (0-255 pressure) — bytes 4-9. A config can drive
    // these from a digital source (full press = 255) or an analog one.
    out_axis("BTN_A",     0, 255);
    out_axis("BTN_B",     0, 255);
    out_axis("BTN_X",     0, 255);
    out_axis("BTN_Y",     0, 255);
    out_axis("BTN_BLACK", 0, 255);
    out_axis("BTN_WHITE", 0, 255);

    // Analog triggers (0-255) — bytes 10-11.
    out_axis("LEFT_TRIGGER",  0, 255);
    out_axis("RIGHT_TRIGGER", 0, 255);

    // Analog sticks (-32768..32767) — bytes 12-19, int16 little-endian.
    out_axis("LEFT_STICK_X",  -32768, 32767);
    out_axis("LEFT_STICK_Y",  -32768, 32767);
    out_axis("RIGHT_STICK_X", -32768, 32767);
    out_axis("RIGHT_STICK_Y", -32768, 32767);
};

///////////////////////////////////////////////////////////////////////////////
// pack() — build the 20-byte XID input report. The exact inverse of
// modules/input/xboxog_winusb.qc parse().

void() pack =
{
    set_report_byte(0, 0x00);   // report type
    set_report_byte(1, 0x14);   // report length = 20

    set_report_byte(2, get_buttons() & 0xFF);   // digital button bitmask
    // byte 3: reserved — left 0 (the buffer is zeroed each pack()).

    set_report_byte(4, get_axis("BTN_A"));
    set_report_byte(5, get_axis("BTN_B"));
    set_report_byte(6, get_axis("BTN_X"));
    set_report_byte(7, get_axis("BTN_Y"));
    set_report_byte(8, get_axis("BTN_BLACK"));
    set_report_byte(9, get_axis("BTN_WHITE"));

    set_report_byte(10, get_axis("LEFT_TRIGGER"));
    set_report_byte(11, get_axis("RIGHT_TRIGGER"));

    // Sticks are int16 LE, written verbatim. Axis DIRECTION is a config concern
    // (the `invert=` option), never hidden in the module — same as xbox360_usb.
    // A hidden negate here fights the config and makes inversion impossible to
    // reason about, so we do NOT do it: an earlier `-get_axis(Y)` here plus a
    // config `invert=true` was a double flip that showed Y upside-down on a real
    // Xbox. If your console shows Y inverted, flip `invert=` in the config.
    set_report_word(12, get_axis("LEFT_STICK_X"));
    set_report_word(14, get_axis("LEFT_STICK_Y"));
    set_report_word(16, get_axis("RIGHT_STICK_X"));
    set_report_word(18, get_axis("RIGHT_STICK_Y"));
};

///////////////////////////////////////////////////////////////////////////////
// on_output() — console -> device on EP 0x02. The 6-byte OG Xbox rumble packet:
//   [0]    = 0x00 (type)      [1]    = 0x06 (length)
//   [2..3] = left  actuator, 16-bit LE (level in high byte [3])
//   [4..5] = right actuator, 16-bit LE (level in high byte [5])

void(bytes raw) on_output =
{
    if (raw[0] == 0x00) {
        set_out_feedback("RUMBLE_LEFT",  raw[3]);
        set_out_feedback("RUMBLE_RIGHT", raw[5]);
        // Mono force magnitude for the wheel/FFB path (raw[3] = left/primary force;
        // for Colin McRae's EP0 mono report every force byte equals this).
        set_out_feedback("WHEELFEEDBACK", raw[3]);
    }
};

///////////////////////////////////////////////////////////////////////////////
// on_control() — answer the XID vendor requests the console makes on EP0 during
// enumeration. All are device-to-host, vendor, interface (bmRequestType 0xC1).
// Bytes are pasted from the real controller's --usb capture. An unrecognised
// request returns no bytes (empty) — the engine completes it with a zero-length
// stage; the console only relies on the three below.

bytes(int bmReqType, int bReq, int wValue, int wIndex, int wLength) on_control =
{
    // GET_DESCRIPTOR(XID): bRequest 0x06, wValue 0x4200.
    // bcdXid 0x0100, bType 0x01 (game controller), bSubType 0x02 (gamepad S),
    // max input 20, max output 6, no alternate product ids (all 0xFFFF).
    if (bReq == 0x06 && wValue == 0x4200) {
        return hex("10 42 00 01 01 02 14 06 FF FF FF FF FF FF FF FF");
    }

    // GET_CAPABILITIES: bRequest 0x01. wValue high byte selects the report —
    // 0x0100 = input (which controls CAN report), 0x0200 = output (rumble).
    // 0xFF marks a present field; 0x00 an unused byte (byte 3 is the reserved gap).
    if (bReq == 0x01 && wValue == 0x0100) {
        return hex("00 14 FF 00 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF");
    }
    if (bReq == 0x01 && wValue == 0x0200) {
        return hex("00 06 FF FF FF FF");
    }

    return hex("");   // unrecognised vendor request
};
