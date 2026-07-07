// Phidimus test gamepad — usb_device output module (Engine 4.0).
//
// A deliberately GENERIC HID gamepad: every standard control type a basic pad can
// expose, so it doubles as (a) a self-test target that proves the engine + a
// config are actually running and sending data, and (b) a low-effort real output
// — there is nothing stopping an end user from binding to testpad_usb for casual
// use. For a dependable, game-recognised pad use a specific module instead
// (xbox360_usb, ps5_usb); they are more work to set up but far more reliable.
//
// Controls (all the generic HID inputs joy.cpl / DirectInput understands):
//   - 16 buttons                     (BTN_1 .. BTN_16)
//   - hat switch / D-pad, 8-way      (HAT_UP / HAT_DOWN / HAT_LEFT / HAT_RIGHT)
//   - left stick   X, Y    signed    (-127..127, centred 0)
//   - right stick  Rx, Ry  signed    (-127..127, centred 0)
//   - triggers     Z, Rz   unsigned  (0..255, rest 0)
//
// 9-byte input report: [btn0-7][btn8-15][hat+pad][X][Y][Rx][Ry][Z][Rz].
// Enumerates as "Phidimus Test Gamepad" once an OS attaches it.

string MODULE_ID      = "testpad_usb";
string MODULE_NAME    = "Phidimus Test Gamepad (USB)";
string MODULE_VERSION = "2.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.0.0";
string DRIVER         = "usb_device";

// USB identity. The engine synthesises the 18-byte device descriptor from these.
int    USB_VID          = 0x1209;   // pid.codes test VID
int    USB_PID          = 0x5050;
int    USB_BCD_DEVICE   = 0x0100;
string USB_MANUFACTURER = "Phidimus";
string USB_PRODUCT      = "Phidimus Test Gamepad";
string USB_SERIAL       = "PHID-0001";

void() declare_usb =
{
    // Configuration blob: config(9) + interface(9, HID class) + HID(9) +
    // endpoint(7). wTotalLength=0x22; HID report descriptor length=0x4E (78).
    usb_config(
        "09 02 22 00 01 01 00 80 32"   // configuration
        "09 04 00 00 01 03 00 00 00"   // interface 0: class 03 (HID)
        "09 21 11 01 00 01 22 4E 00"   // HID descriptor (report len 0x4E)
        "07 05 81 03 09 00 04"         // EP 0x81 IN, interrupt, 9 B, 4 ms
    );

    // HID report descriptor: 16 buttons + 8-way hat + X/Y/Rx/Ry (signed) +
    // Z/Rz (unsigned). Item order defines the report byte order below.
    usb_hid_report_descriptor(
        "05 01 09 05 A1 01"                                  // Usage Page Desktop, Game Pad, Collection
        "05 09 19 01 29 10 15 00 25 01 75 01 95 10 81 02"    // 16 buttons (1 bit each)
        "05 01 09 39 15 00 25 07 75 04 95 01 81 42"          // hat switch: 4 bits, logical 0-7, Null
        "75 04 95 01 81 03"                                  // 4-bit constant padding (byte-align)
        "05 01 09 30 09 31 09 33 09 34 15 81 25 7F 75 08 95 04 81 02"  // X Y Rx Ry, signed -127..127
        "09 32 09 35 15 00 26 FF 00 75 08 95 02 81 02"       // Z Rz, unsigned 0..255
        "C0"                                                 // End Collection
    );

    in_endpoint(0x81);
};

void() declare_signals =
{
    report_len(9);   // [btn0-7][btn8-15][hat][X][Y][Rx][Ry][Z][Rz]

    // 16 buttons → report bits 0..15 (bytes 0-1).
    out_btn("BTN_1",  0x0001);
    out_btn("BTN_2",  0x0002);
    out_btn("BTN_3",  0x0004);
    out_btn("BTN_4",  0x0008);
    out_btn("BTN_5",  0x0010);
    out_btn("BTN_6",  0x0020);
    out_btn("BTN_7",  0x0040);
    out_btn("BTN_8",  0x0080);
    out_btn("BTN_9",  0x0100);
    out_btn("BTN_10", 0x0200);
    out_btn("BTN_11", 0x0400);
    out_btn("BTN_12", 0x0800);
    out_btn("BTN_13", 0x1000);
    out_btn("BTN_14", 0x2000);
    out_btn("BTN_15", 0x4000);
    out_btn("BTN_16", 0x8000);

    // Hat directions are logical signals (bits 16..19) — pack() folds them into
    // the 4-bit hat nibble. They are NOT report buttons, so they don't collide
    // with the 16 above. Map a controller's D-pad to these.
    out_btn("HAT_UP",    0x10000);
    out_btn("HAT_DOWN",  0x20000);
    out_btn("HAT_LEFT",  0x40000);
    out_btn("HAT_RIGHT", 0x80000);

    // Sticks (signed, centred 0) and triggers (unsigned, rest 0).
    out_axis("X",  -127, 127);
    out_axis("Y",  -127, 127);
    out_axis("RX", -127, 127);
    out_axis("RY", -127, 127);
    out_axis("Z",   0, 255);
    out_axis("RZ",  0, 255);
};

void() pack =
{
    local int b = get_buttons();

    // Bytes 0-1: the 16 report buttons.
    set_report_byte(0, b & 0xFF);
    set_report_byte(1, (b >> 8) & 0xFF);

    // Byte 2: hat nibble. 0=N,1=NE,2=E,3=SE,4=S,5=SW,6=W,7=NW; 15 = centred/null.
    // Encoded from the four HAT_* logical buttons (bits 16..19).
    local int up    = b & 0x10000;
    local int down  = b & 0x20000;
    local int left  = b & 0x40000;
    local int right = b & 0x80000;
    local int hat = 15;
    if (up)
    {
        if (right) { hat = 1; }
        else { if (left) { hat = 7; } else { hat = 0; } }
    }
    else
    {
        if (down)
        {
            if (right) { hat = 3; }
            else { if (left) { hat = 5; } else { hat = 4; } }
        }
        else
        {
            if (right) { hat = 2; }
            else { if (left) { hat = 6; } }
        }
    }
    set_report_byte(2, hat & 0x0F);

    // Bytes 3-8: the six axes, in descriptor order.
    set_report_byte(3, get_axis("X"));
    set_report_byte(4, get_axis("Y"));
    set_report_byte(5, get_axis("RX"));
    set_report_byte(6, get_axis("RY"));
    set_report_byte(7, get_axis("Z"));
    set_report_byte(8, get_axis("RZ"));
};
