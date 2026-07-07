// Generic Mouse Input module
// Polls cursor delta and button state at ~1000 Hz via GetCursorPos / GetAsyncKeyState.
//
// Axes MOUSE_X and MOUSE_Y report pixels moved since the last poll (typically
// 0â€“5 px at normal speeds; spikes to 20+ px during fast sweeps).
// Use the mapper 'sensitivity' and 'out_max' overrides to scale for your output.

string MODULE_ID      = "mouse_input";
string MODULE_NAME    = "Generic Mouse Input";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "3.0.0";
int    VID            = 0x0000;
int    PID            = 0x0000;
string DRIVER         = "mouse_input";

// 5-byte report format (from mouse_input_windows.go):
//   Byte 0:   button bitmask (bit0=LMB, bit1=RMB, bit2=MMB, bit3=X1, bit4=X2)
//   Bytes 1-2: delta X  (signed int16, little-endian)
//   Bytes 3-4: delta Y  (signed int16, little-endian)

void() declare_signals =
{
    btn("MOUSE_BTN_LEFT");    // left mouse button
    btn("MOUSE_BTN_RIGHT");   // right mouse button
    btn("MOUSE_BTN_MIDDLE");  // middle / scroll-wheel click
    btn("MOUSE_BTN_X1");      // extra button 1 (back)
    btn("MOUSE_BTN_X2");      // extra button 2 (forward)

    // Signed pixel delta per poll interval (~1 ms).
    // Range covers realistic fast-swipe values; map to a smaller out_max
    // (e.g. out_max: 10) for controllable mouse output.
    axis("MOUSE_X", -32767, 32767);
    axis("MOUSE_Y", -32767, 32767);
};

void(bytes raw) parse =
{
    set_btn("MOUSE_BTN_LEFT",   raw[0] & 0x01);
    set_btn("MOUSE_BTN_RIGHT",  raw[0] & 0x02);
    set_btn("MOUSE_BTN_MIDDLE", raw[0] & 0x04);
    set_btn("MOUSE_BTN_X1",     raw[0] & 0x08);
    set_btn("MOUSE_BTN_X2",     raw[0] & 0x10);

    // Reconstruct signed int16 from two little-endian bytes.
    local int dx = raw[1] | (raw[2] << 8);
    if (dx > 32767) { dx = dx - 65536; }
    set_axis("MOUSE_X", dx);

    local int dy = raw[3] | (raw[4] << 8);
    if (dy > 32767) { dy = dy - 65536; }
    set_axis("MOUSE_Y", dy);
};
