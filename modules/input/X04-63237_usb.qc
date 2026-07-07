// SideWinder Game Pad Pro USB version 1.1
//
// Reports raw device state only — no policy. The two top triggers are exposed as
// the digital buttons BTN_LT / BTN_RT, and the SHIFT button as BTN_SHIFT; what
// SHIFT *does* (route the triggers to shoulder buttons vs analog axes) is decided
// in the config with modifier guards, not baked in here. See
// config/SidewinderProPad_to_xbox360.ini.

string MODULE_ID      = "X04-63237_usb";
string MODULE_NAME    = "SideWinder Game Pad Pro (USB)";
string MODULE_VERSION = "2.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.1.0";
int    VID            = 0x045E;
int    PID            = 0x0026;
string DRIVER         = "hid_input";

void() declare_signals =
{
    btn("BTN_A");
    btn("BTN_B");
    btn("BTN_C");
    btn("BTN_X");
    btn("BTN_Y");
    btn("BTN_Z");
    // Top triggers (raw digital buttons) and the SHIFT button. The config decides
    // what SHIFT does with the triggers via modifier guards.
    btn("BTN_LT");
    btn("BTN_RT");
    btn("BTN_SHIFT");

    axis("LEFT_STICK_X",   0, 255);
    axis("LEFT_STICK_Y",   0, 255);
};


void(bytes raw) parse =
{
    // D-pad axes are SIGNED bytes centred on 0x00 (verified with --hids):
    //   raw[1] = X:  0x80 (-128) = left   0x00 = centre   0x7F (+127) = right
    //   raw[2] = Y:  0x80 (-128) = up     0x00 = centre   0x7F (+127) = down
    // +128 converts two's complement to the declared 0-255 range (centre 128),
    // matching the ps5ds module's convention: X 0=left, Y 0=up.
    set_axis("LEFT_STICK_X", (raw[1] + 128) & 0xFF);
    set_axis("LEFT_STICK_Y", (raw[2] + 128) & 0xFF);

    // Face buttons: byte 3 low six bits
    set_btn("BTN_A", raw[3] & 0x01);
    set_btn("BTN_B", raw[3] & 0x02);
    set_btn("BTN_C", raw[3] & 0x04);
    set_btn("BTN_X", raw[3] & 0x08);
    set_btn("BTN_Y", raw[3] & 0x10);
    set_btn("BTN_Z", raw[3] & 0x20);

    // Top triggers (raw) and SHIFT — reported as-is, no routing.
    set_btn("BTN_LT",    raw[3] & 0x40);
    set_btn("BTN_RT",    raw[3] & 0x80);
    set_btn("BTN_SHIFT", raw[4] & 0x01);
};
