// Generic Keyboard Output module
// Emulates a keyboard via Win32 SendInput.  Each key is exposed as an axis
// with range 0-1 so the mapper can route buttons or thresholded axes to it.
//
// In your config, map input signals to keys using the 'axes:' section:
//
//   outputs:
//     - module: keyboard_output
//       axes:
//         - { from: BTN_CROSS, to: KEY_SPACE }
//         - { from: BTN_SQUARE, to: KEY_E }
//         - { from: LEFT_STICK_X, to: KEY_D, sensitivity: 2.0, out_min: 0 }
//
// The 256-byte output report uses each byte as a VK code:
//   report[vk] = 1 key is pressed; 0 key is released.
// SendInput is called only on transitions to minimise system load.

string MODULE_ID      = "keyboard_output";
string MODULE_NAME    = "Generic Keyboard Output";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "3.0.0";
string DRIVER         = "sendinput_kb";

void() declare_signals =
{
    report_len(256);  // one byte per VK code

    // Editing / control 
    out_axis("KEY_BACKSPACE",   0, 1);   // 0x08
    out_axis("KEY_TAB",         0, 1);   // 0x09
    out_axis("KEY_ENTER",       0, 1);   // 0x0D
    out_axis("KEY_PAUSE",       0, 1);   // 0x13
    out_axis("KEY_CAPSLOCK",    0, 1);   // 0x14
    out_axis("KEY_ESC",         0, 1);   // 0x1B
    out_axis("KEY_SPACE",       0, 1);   // 0x20

    // Navigation cluster
    out_axis("KEY_PAGEUP",      0, 1);   // 0x21
    out_axis("KEY_PAGEDOWN",    0, 1);   // 0x22
    out_axis("KEY_END",         0, 1);   // 0x23
    out_axis("KEY_HOME",        0, 1);   // 0x24
    out_axis("KEY_LEFT",        0, 1);   // 0x25
    out_axis("KEY_UP",          0, 1);   // 0x26
    out_axis("KEY_RIGHT",       0, 1);   // 0x27
    out_axis("KEY_DOWN",        0, 1);   // 0x28
    out_axis("KEY_PRINTSCREEN", 0, 1);   // 0x2C
    out_axis("KEY_INSERT",      0, 1);   // 0x2D
    out_axis("KEY_DELETE",      0, 1);   // 0x2E

    // Number row
    out_axis("KEY_0", 0, 1);             // 0x30
    out_axis("KEY_1", 0, 1);             // 0x31
    out_axis("KEY_2", 0, 1);             // 0x32
    out_axis("KEY_3", 0, 1);             // 0x33
    out_axis("KEY_4", 0, 1);             // 0x34
    out_axis("KEY_5", 0, 1);             // 0x35
    out_axis("KEY_6", 0, 1);             // 0x36
    out_axis("KEY_7", 0, 1);             // 0x37
    out_axis("KEY_8", 0, 1);             // 0x38
    out_axis("KEY_9", 0, 1);             // 0x39

    // Alphabet
    out_axis("KEY_A", 0, 1);             // 0x41
    out_axis("KEY_B", 0, 1);             // 0x42
    out_axis("KEY_C", 0, 1);             // 0x43
    out_axis("KEY_D", 0, 1);             // 0x44
    out_axis("KEY_E", 0, 1);             // 0x45
    out_axis("KEY_F", 0, 1);             // 0x46
    out_axis("KEY_G", 0, 1);             // 0x47
    out_axis("KEY_H", 0, 1);             // 0x48
    out_axis("KEY_I", 0, 1);             // 0x49
    out_axis("KEY_J", 0, 1);             // 0x4A
    out_axis("KEY_K", 0, 1);             // 0x4B
    out_axis("KEY_L", 0, 1);             // 0x4C
    out_axis("KEY_M", 0, 1);             // 0x4D
    out_axis("KEY_N", 0, 1);             // 0x4E
    out_axis("KEY_O", 0, 1);             // 0x4F
    out_axis("KEY_P", 0, 1);             // 0x50
    out_axis("KEY_Q", 0, 1);             // 0x51
    out_axis("KEY_R", 0, 1);             // 0x52
    out_axis("KEY_S", 0, 1);             // 0x53
    out_axis("KEY_T", 0, 1);             // 0x54
    out_axis("KEY_U", 0, 1);             // 0x55
    out_axis("KEY_V", 0, 1);             // 0x56
    out_axis("KEY_W", 0, 1);             // 0x57
    out_axis("KEY_X", 0, 1);             // 0x58
    out_axis("KEY_Y", 0, 1);             // 0x59
    out_axis("KEY_Z", 0, 1);             // 0x5A

    // Windows / apps
    out_axis("KEY_LWIN", 0, 1);          // 0x5B
    out_axis("KEY_RWIN", 0, 1);          // 0x5C
    out_axis("KEY_APPS", 0, 1);          // 0x5D

    // Numpad
    out_axis("KEY_NUM0",   0, 1);        // 0x60
    out_axis("KEY_NUM1",   0, 1);        // 0x61
    out_axis("KEY_NUM2",   0, 1);        // 0x62
    out_axis("KEY_NUM3",   0, 1);        // 0x63
    out_axis("KEY_NUM4",   0, 1);        // 0x64
    out_axis("KEY_NUM5",   0, 1);        // 0x65
    out_axis("KEY_NUM6",   0, 1);        // 0x66
    out_axis("KEY_NUM7",   0, 1);        // 0x67
    out_axis("KEY_NUM8",   0, 1);        // 0x68
    out_axis("KEY_NUM9",   0, 1);        // 0x69
    out_axis("KEY_NUMMUL", 0, 1);        // 0x6A
    out_axis("KEY_NUMADD", 0, 1);        // 0x6B
    out_axis("KEY_NUMSUB", 0, 1);        // 0x6D
    out_axis("KEY_NUMDEC", 0, 1);        // 0x6E
    out_axis("KEY_NUMDIV", 0, 1);        // 0x6F

    // Function keys
    out_axis("KEY_F1",  0, 1);           // 0x70
    out_axis("KEY_F2",  0, 1);           // 0x71
    out_axis("KEY_F3",  0, 1);           // 0x72
    out_axis("KEY_F4",  0, 1);           // 0x73
    out_axis("KEY_F5",  0, 1);           // 0x74
    out_axis("KEY_F6",  0, 1);           // 0x75
    out_axis("KEY_F7",  0, 1);           // 0x76
    out_axis("KEY_F8",  0, 1);           // 0x77
    out_axis("KEY_F9",  0, 1);           // 0x78
    out_axis("KEY_F10", 0, 1);           // 0x79
    out_axis("KEY_F11", 0, 1);           // 0x7A
    out_axis("KEY_F12", 0, 1);           // 0x7B

    // Lock keys
    out_axis("KEY_NUMLOCK",    0, 1);    // 0x90
    out_axis("KEY_SCROLLLOCK", 0, 1);   // 0x91

    // Modifier keys
    out_axis("KEY_LSHIFT", 0, 1);        // 0xA0
    out_axis("KEY_RSHIFT", 0, 1);        // 0xA1
    out_axis("KEY_LCTRL",  0, 1);        // 0xA2
    out_axis("KEY_RCTRL",  0, 1);        // 0xA3
    out_axis("KEY_LALT",   0, 1);        // 0xA4
    out_axis("KEY_RALT",   0, 1);        // 0xA5

    // Punctuation
    out_axis("KEY_SEMICOLON",  0, 1);    // 0xBA  ;:
    out_axis("KEY_EQUALS",     0, 1);    // 0xBB  =+
    out_axis("KEY_COMMA",      0, 1);    // 0xBC  ,<
    out_axis("KEY_MINUS",      0, 1);    // 0xBD  -_
    out_axis("KEY_PERIOD",     0, 1);    // 0xBE  .>
    out_axis("KEY_SLASH",      0, 1);    // 0xBF  /?
    out_axis("KEY_GRAVE",      0, 1);    // 0xC0  `~
    out_axis("KEY_LBRACKET",   0, 1);    // 0xDB  [{
    out_axis("KEY_BACKSLASH",  0, 1);    // 0xDC  \|
    out_axis("KEY_RBRACKET",   0, 1);    // 0xDD  ]}
    out_axis("KEY_APOSTROPHE", 0, 1);    // 0xDE  '"
};

void() pack =
{
    // Each set_report_byte(vk_code, get_axis("KEY_NAME")) writes the 0/1 key
    // state into the correct slot of the 256-byte report.

    // Editing / control
    set_report_byte(0x08, get_axis("KEY_BACKSPACE"));
    set_report_byte(0x09, get_axis("KEY_TAB"));
    set_report_byte(0x0D, get_axis("KEY_ENTER"));
    set_report_byte(0x13, get_axis("KEY_PAUSE"));
    set_report_byte(0x14, get_axis("KEY_CAPSLOCK"));
    set_report_byte(0x1B, get_axis("KEY_ESC"));
    set_report_byte(0x20, get_axis("KEY_SPACE"));

    // Navigation
    set_report_byte(0x21, get_axis("KEY_PAGEUP"));
    set_report_byte(0x22, get_axis("KEY_PAGEDOWN"));
    set_report_byte(0x23, get_axis("KEY_END"));
    set_report_byte(0x24, get_axis("KEY_HOME"));
    set_report_byte(0x25, get_axis("KEY_LEFT"));
    set_report_byte(0x26, get_axis("KEY_UP"));
    set_report_byte(0x27, get_axis("KEY_RIGHT"));
    set_report_byte(0x28, get_axis("KEY_DOWN"));
    set_report_byte(0x2C, get_axis("KEY_PRINTSCREEN"));
    set_report_byte(0x2D, get_axis("KEY_INSERT"));
    set_report_byte(0x2E, get_axis("KEY_DELETE"));

    // Number row
    set_report_byte(0x30, get_axis("KEY_0"));
    set_report_byte(0x31, get_axis("KEY_1"));
    set_report_byte(0x32, get_axis("KEY_2"));
    set_report_byte(0x33, get_axis("KEY_3"));
    set_report_byte(0x34, get_axis("KEY_4"));
    set_report_byte(0x35, get_axis("KEY_5"));
    set_report_byte(0x36, get_axis("KEY_6"));
    set_report_byte(0x37, get_axis("KEY_7"));
    set_report_byte(0x38, get_axis("KEY_8"));
    set_report_byte(0x39, get_axis("KEY_9"));

    // Alphabet
    set_report_byte(0x41, get_axis("KEY_A"));
    set_report_byte(0x42, get_axis("KEY_B"));
    set_report_byte(0x43, get_axis("KEY_C"));
    set_report_byte(0x44, get_axis("KEY_D"));
    set_report_byte(0x45, get_axis("KEY_E"));
    set_report_byte(0x46, get_axis("KEY_F"));
    set_report_byte(0x47, get_axis("KEY_G"));
    set_report_byte(0x48, get_axis("KEY_H"));
    set_report_byte(0x49, get_axis("KEY_I"));
    set_report_byte(0x4A, get_axis("KEY_J"));
    set_report_byte(0x4B, get_axis("KEY_K"));
    set_report_byte(0x4C, get_axis("KEY_L"));
    set_report_byte(0x4D, get_axis("KEY_M"));
    set_report_byte(0x4E, get_axis("KEY_N"));
    set_report_byte(0x4F, get_axis("KEY_O"));
    set_report_byte(0x50, get_axis("KEY_P"));
    set_report_byte(0x51, get_axis("KEY_Q"));
    set_report_byte(0x52, get_axis("KEY_R"));
    set_report_byte(0x53, get_axis("KEY_S"));
    set_report_byte(0x54, get_axis("KEY_T"));
    set_report_byte(0x55, get_axis("KEY_U"));
    set_report_byte(0x56, get_axis("KEY_V"));
    set_report_byte(0x57, get_axis("KEY_W"));
    set_report_byte(0x58, get_axis("KEY_X"));
    set_report_byte(0x59, get_axis("KEY_Y"));
    set_report_byte(0x5A, get_axis("KEY_Z"));

    // Windows / apps
    set_report_byte(0x5B, get_axis("KEY_LWIN"));
    set_report_byte(0x5C, get_axis("KEY_RWIN"));
    set_report_byte(0x5D, get_axis("KEY_APPS"));

    // Numpad
    set_report_byte(0x60, get_axis("KEY_NUM0"));
    set_report_byte(0x61, get_axis("KEY_NUM1"));
    set_report_byte(0x62, get_axis("KEY_NUM2"));
    set_report_byte(0x63, get_axis("KEY_NUM3"));
    set_report_byte(0x64, get_axis("KEY_NUM4"));
    set_report_byte(0x65, get_axis("KEY_NUM5"));
    set_report_byte(0x66, get_axis("KEY_NUM6"));
    set_report_byte(0x67, get_axis("KEY_NUM7"));
    set_report_byte(0x68, get_axis("KEY_NUM8"));
    set_report_byte(0x69, get_axis("KEY_NUM9"));
    set_report_byte(0x6A, get_axis("KEY_NUMMUL"));
    set_report_byte(0x6B, get_axis("KEY_NUMADD"));
    set_report_byte(0x6D, get_axis("KEY_NUMSUB"));
    set_report_byte(0x6E, get_axis("KEY_NUMDEC"));
    set_report_byte(0x6F, get_axis("KEY_NUMDIV"));

    // Function keys
    set_report_byte(0x70, get_axis("KEY_F1"));
    set_report_byte(0x71, get_axis("KEY_F2"));
    set_report_byte(0x72, get_axis("KEY_F3"));
    set_report_byte(0x73, get_axis("KEY_F4"));
    set_report_byte(0x74, get_axis("KEY_F5"));
    set_report_byte(0x75, get_axis("KEY_F6"));
    set_report_byte(0x76, get_axis("KEY_F7"));
    set_report_byte(0x77, get_axis("KEY_F8"));
    set_report_byte(0x78, get_axis("KEY_F9"));
    set_report_byte(0x79, get_axis("KEY_F10"));
    set_report_byte(0x7A, get_axis("KEY_F11"));
    set_report_byte(0x7B, get_axis("KEY_F12"));

    // Lock keys
    set_report_byte(0x90, get_axis("KEY_NUMLOCK"));
    set_report_byte(0x91, get_axis("KEY_SCROLLLOCK"));

    // Modifiers
    set_report_byte(0xA0, get_axis("KEY_LSHIFT"));
    set_report_byte(0xA1, get_axis("KEY_RSHIFT"));
    set_report_byte(0xA2, get_axis("KEY_LCTRL"));
    set_report_byte(0xA3, get_axis("KEY_RCTRL"));
    set_report_byte(0xA4, get_axis("KEY_LALT"));
    set_report_byte(0xA5, get_axis("KEY_RALT"));

    // Punctuation
    set_report_byte(0xBA, get_axis("KEY_SEMICOLON"));
    set_report_byte(0xBB, get_axis("KEY_EQUALS"));
    set_report_byte(0xBC, get_axis("KEY_COMMA"));
    set_report_byte(0xBD, get_axis("KEY_MINUS"));
    set_report_byte(0xBE, get_axis("KEY_PERIOD"));
    set_report_byte(0xBF, get_axis("KEY_SLASH"));
    set_report_byte(0xC0, get_axis("KEY_GRAVE"));
    set_report_byte(0xDB, get_axis("KEY_LBRACKET"));
    set_report_byte(0xDC, get_axis("KEY_BACKSLASH"));
    set_report_byte(0xDD, get_axis("KEY_RBRACKET"));
    set_report_byte(0xDE, get_axis("KEY_APOSTROPHE"));
};
