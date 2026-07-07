// Generic Mouse Output module
// Emulates a mouse via Win32 SendInput (relative movement mode).
//
// MOUSE_X / MOUSE_Y are pixel deltas sent each output write.
// Range is +-32767 (matching mouse_input) so passive mouse to mouse pass-through
// works at 1:1.  When driving from a controller stick, clamp via out_max:
//
//   axes:
//     - { from: RIGHT_STICK_X, to: MOUSE_X, sensitivity: 2.0, out_max: 30 }
//     - { from: RIGHT_STICK_Y, to: MOUSE_Y, sensitivity: 2.0, out_max: 30 }
//
// For mouse-to-mouse passthrough (just changing device IDs), set passive: true
// in the output binding so MOUSE_X, MOUSE_Y and all buttons forward automatically.

string MODULE_ID      = "mouse_output";
string MODULE_NAME    = "Generic Mouse Output";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "3.0.0";
string DRIVER         = "sendinput_mouse";

// 5-byte report format (consumed by sendinput_mouse_windows.go):
//   Byte 0:   button bitmask  (bit0=LMB, bit1=RMB, bit2=MMB, bit3=X1, bit4=X2)
//   Bytes 1-2: delta X  (signed int16, little-endian)
//   Bytes 3-4: delta Y  (signed int16, little-endian)

void() declare_signals =
{
    report_len(5);

    out_btn("MOUSE_BTN_LEFT",   0x01);
    out_btn("MOUSE_BTN_RIGHT",  0x02);
    out_btn("MOUSE_BTN_MIDDLE", 0x04);
    out_btn("MOUSE_BTN_X1",     0x08);
    out_btn("MOUSE_BTN_X2",     0x10);

    // Pixel delta per output write.  Matches mouse_input range for 1:1
    // passive passthrough.  Use out_max in your config when driving from a
    // controller stick (e.g. out_max=30 for sane sensitivity).
    out_axis("MOUSE_X", -32767, 32767);
    out_axis("MOUSE_Y", -32767, 32767);
};

void() pack =
{
    // Byte 0: button bitmask from the output state.
    set_report_byte(0, get_buttons() & 0xFF);

    // Bytes 1-2: delta X (signed int16, little-endian).
    local int dx = get_axis("MOUSE_X");
    set_report_byte(1, dx & 0xFF);
    set_report_byte(2, (dx >> 8) & 0xFF);

    // Bytes 3-4: delta Y (signed int16, little-endian).
    local int dy = get_axis("MOUSE_Y");
    set_report_byte(3, dy & 0xFF);
    set_report_byte(4, (dy >> 8) & 0xFF);
};
