// Generic Keyboard Input module
// Polls all Windows virtual-key states at ~1000 Hz via GetAsyncKeyState.
// Each declared signal corresponds to one VK code â€” use the signal name in
// your config's 'from:' field just like any other input button.
//
// To send a key to an output device use keyboard_output.qc.
// To send a key to a virtual gamepad map buttons to controller buttons/axes.

string MODULE_ID      = "keyboard_input";
string MODULE_NAME    = "Generic Keyboard Input";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "3.0.0";
// No VID/PID â€” software device, not a physical HID peripheral.
int    VID            = 0x0000;
int    PID            = 0x0000;
string DRIVER         = "keyboard_input";

// The driver returns a 256-byte report where raw[vk] = 1 when the key is down.
// VK codes are Windows Virtual-Key codes.  See:
// https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes

void() declare_signals =
{
    // â”€â”€ Editing / control â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_BACKSPACE");   // 0x08  VK_BACK
    btn("KEY_TAB");         // 0x09  VK_TAB
    btn("KEY_ENTER");       // 0x0D  VK_RETURN
    btn("KEY_PAUSE");       // 0x13  VK_PAUSE
    btn("KEY_CAPSLOCK");    // 0x14  VK_CAPITAL
    btn("KEY_ESC");         // 0x1B  VK_ESCAPE
    btn("KEY_SPACE");       // 0x20  VK_SPACE

    // â”€â”€ Navigation cluster â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_PAGEUP");      // 0x21  VK_PRIOR
    btn("KEY_PAGEDOWN");    // 0x22  VK_NEXT
    btn("KEY_END");         // 0x23  VK_END
    btn("KEY_HOME");        // 0x24  VK_HOME
    btn("KEY_LEFT");        // 0x25  VK_LEFT
    btn("KEY_UP");          // 0x26  VK_UP
    btn("KEY_RIGHT");       // 0x27  VK_RIGHT
    btn("KEY_DOWN");        // 0x28  VK_DOWN
    btn("KEY_PRINTSCREEN"); // 0x2C  VK_SNAPSHOT
    btn("KEY_INSERT");      // 0x2D  VK_INSERT
    btn("KEY_DELETE");      // 0x2E  VK_DELETE

    // â”€â”€ Number row (0â€“9) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_0");           // 0x30
    btn("KEY_1");           // 0x31
    btn("KEY_2");           // 0x32
    btn("KEY_3");           // 0x33
    btn("KEY_4");           // 0x34
    btn("KEY_5");           // 0x35
    btn("KEY_6");           // 0x36
    btn("KEY_7");           // 0x37
    btn("KEY_8");           // 0x38
    btn("KEY_9");           // 0x39

    // â”€â”€ Alphabet (Aâ€“Z) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_A");           // 0x41
    btn("KEY_B");           // 0x42
    btn("KEY_C");           // 0x43
    btn("KEY_D");           // 0x44
    btn("KEY_E");           // 0x45
    btn("KEY_F");           // 0x46
    btn("KEY_G");           // 0x47
    btn("KEY_H");           // 0x48
    btn("KEY_I");           // 0x49
    btn("KEY_J");           // 0x4A
    btn("KEY_K");           // 0x4B
    btn("KEY_L");           // 0x4C
    btn("KEY_M");           // 0x4D
    btn("KEY_N");           // 0x4E
    btn("KEY_O");           // 0x4F
    btn("KEY_P");           // 0x50
    btn("KEY_Q");           // 0x51
    btn("KEY_R");           // 0x52
    btn("KEY_S");           // 0x53
    btn("KEY_T");           // 0x54
    btn("KEY_U");           // 0x55
    btn("KEY_V");           // 0x56
    btn("KEY_W");           // 0x57
    btn("KEY_X");           // 0x58
    btn("KEY_Y");           // 0x59
    btn("KEY_Z");           // 0x5A

    // â”€â”€ Windows / apps keys â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_LWIN");        // 0x5B  VK_LWIN
    btn("KEY_RWIN");        // 0x5C  VK_RWIN
    btn("KEY_APPS");        // 0x5D  VK_APPS  (context menu key)

    // â”€â”€ Numpad â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_NUM0");        // 0x60  VK_NUMPAD0
    btn("KEY_NUM1");        // 0x61
    btn("KEY_NUM2");        // 0x62
    btn("KEY_NUM3");        // 0x63
    btn("KEY_NUM4");        // 0x64
    btn("KEY_NUM5");        // 0x65
    btn("KEY_NUM6");        // 0x66
    btn("KEY_NUM7");        // 0x67
    btn("KEY_NUM8");        // 0x68
    btn("KEY_NUM9");        // 0x69
    btn("KEY_NUMMUL");      // 0x6A  VK_MULTIPLY  (*)
    btn("KEY_NUMADD");      // 0x6B  VK_ADD       (+)
    btn("KEY_NUMSUB");      // 0x6D  VK_SUBTRACT  (-)
    btn("KEY_NUMDEC");      // 0x6E  VK_DECIMAL   (.)
    btn("KEY_NUMDIV");      // 0x6F  VK_DIVIDE    (/)

    // â”€â”€ Function keys â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_F1");          // 0x70
    btn("KEY_F2");          // 0x71
    btn("KEY_F3");          // 0x72
    btn("KEY_F4");          // 0x73
    btn("KEY_F5");          // 0x74
    btn("KEY_F6");          // 0x75
    btn("KEY_F7");          // 0x76
    btn("KEY_F8");          // 0x77
    btn("KEY_F9");          // 0x78
    btn("KEY_F10");         // 0x79
    btn("KEY_F11");         // 0x7A
    btn("KEY_F12");         // 0x7B

    // â”€â”€ Lock keys â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_NUMLOCK");     // 0x90  VK_NUMLOCK
    btn("KEY_SCROLLLOCK");  // 0x91  VK_SCROLL

    // â”€â”€ Modifier keys (sided) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_LSHIFT");      // 0xA0  VK_LSHIFT
    btn("KEY_RSHIFT");      // 0xA1  VK_RSHIFT
    btn("KEY_LCTRL");       // 0xA2  VK_LCONTROL
    btn("KEY_RCTRL");       // 0xA3  VK_RCONTROL
    btn("KEY_LALT");        // 0xA4  VK_LMENU
    btn("KEY_RALT");        // 0xA5  VK_RMENU

    // â”€â”€ OEM / punctuation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    btn("KEY_SEMICOLON");   // 0xBA  VK_OEM_1   ;:
    btn("KEY_EQUALS");      // 0xBB  VK_OEM_PLUS  =+
    btn("KEY_COMMA");       // 0xBC  VK_OEM_COMMA  ,<
    btn("KEY_MINUS");       // 0xBD  VK_OEM_MINUS  -_
    btn("KEY_PERIOD");      // 0xBE  VK_OEM_PERIOD  .>
    btn("KEY_SLASH");       // 0xBF  VK_OEM_2   /?
    btn("KEY_GRAVE");       // 0xC0  VK_OEM_3   `~
    btn("KEY_LBRACKET");    // 0xDB  VK_OEM_4   [{
    btn("KEY_BACKSLASH");   // 0xDC  VK_OEM_5   \|
    btn("KEY_RBRACKET");    // 0xDD  VK_OEM_6   ]}
    btn("KEY_APOSTROPHE");  // 0xDE  VK_OEM_7   '"
};

void(bytes raw) parse =
{
    // Editing / control
    set_btn("KEY_BACKSPACE",   raw[0x08]);
    set_btn("KEY_TAB",         raw[0x09]);
    set_btn("KEY_ENTER",       raw[0x0D]);
    set_btn("KEY_PAUSE",       raw[0x13]);
    set_btn("KEY_CAPSLOCK",    raw[0x14]);
    set_btn("KEY_ESC",         raw[0x1B]);
    set_btn("KEY_SPACE",       raw[0x20]);

    // Navigation
    set_btn("KEY_PAGEUP",      raw[0x21]);
    set_btn("KEY_PAGEDOWN",    raw[0x22]);
    set_btn("KEY_END",         raw[0x23]);
    set_btn("KEY_HOME",        raw[0x24]);
    set_btn("KEY_LEFT",        raw[0x25]);
    set_btn("KEY_UP",          raw[0x26]);
    set_btn("KEY_RIGHT",       raw[0x27]);
    set_btn("KEY_DOWN",        raw[0x28]);
    set_btn("KEY_PRINTSCREEN", raw[0x2C]);
    set_btn("KEY_INSERT",      raw[0x2D]);
    set_btn("KEY_DELETE",      raw[0x2E]);

    // Number row
    set_btn("KEY_0", raw[0x30]);
    set_btn("KEY_1", raw[0x31]);
    set_btn("KEY_2", raw[0x32]);
    set_btn("KEY_3", raw[0x33]);
    set_btn("KEY_4", raw[0x34]);
    set_btn("KEY_5", raw[0x35]);
    set_btn("KEY_6", raw[0x36]);
    set_btn("KEY_7", raw[0x37]);
    set_btn("KEY_8", raw[0x38]);
    set_btn("KEY_9", raw[0x39]);

    // Alphabet
    set_btn("KEY_A", raw[0x41]);
    set_btn("KEY_B", raw[0x42]);
    set_btn("KEY_C", raw[0x43]);
    set_btn("KEY_D", raw[0x44]);
    set_btn("KEY_E", raw[0x45]);
    set_btn("KEY_F", raw[0x46]);
    set_btn("KEY_G", raw[0x47]);
    set_btn("KEY_H", raw[0x48]);
    set_btn("KEY_I", raw[0x49]);
    set_btn("KEY_J", raw[0x4A]);
    set_btn("KEY_K", raw[0x4B]);
    set_btn("KEY_L", raw[0x4C]);
    set_btn("KEY_M", raw[0x4D]);
    set_btn("KEY_N", raw[0x4E]);
    set_btn("KEY_O", raw[0x4F]);
    set_btn("KEY_P", raw[0x50]);
    set_btn("KEY_Q", raw[0x51]);
    set_btn("KEY_R", raw[0x52]);
    set_btn("KEY_S", raw[0x53]);
    set_btn("KEY_T", raw[0x54]);
    set_btn("KEY_U", raw[0x55]);
    set_btn("KEY_V", raw[0x56]);
    set_btn("KEY_W", raw[0x57]);
    set_btn("KEY_X", raw[0x58]);
    set_btn("KEY_Y", raw[0x59]);
    set_btn("KEY_Z", raw[0x5A]);

    // Windows / apps
    set_btn("KEY_LWIN", raw[0x5B]);
    set_btn("KEY_RWIN", raw[0x5C]);
    set_btn("KEY_APPS", raw[0x5D]);

    // Numpad
    set_btn("KEY_NUM0",   raw[0x60]);
    set_btn("KEY_NUM1",   raw[0x61]);
    set_btn("KEY_NUM2",   raw[0x62]);
    set_btn("KEY_NUM3",   raw[0x63]);
    set_btn("KEY_NUM4",   raw[0x64]);
    set_btn("KEY_NUM5",   raw[0x65]);
    set_btn("KEY_NUM6",   raw[0x66]);
    set_btn("KEY_NUM7",   raw[0x67]);
    set_btn("KEY_NUM8",   raw[0x68]);
    set_btn("KEY_NUM9",   raw[0x69]);
    set_btn("KEY_NUMMUL", raw[0x6A]);
    set_btn("KEY_NUMADD", raw[0x6B]);
    set_btn("KEY_NUMSUB", raw[0x6D]);
    set_btn("KEY_NUMDEC", raw[0x6E]);
    set_btn("KEY_NUMDIV", raw[0x6F]);

    // Function keys
    set_btn("KEY_F1",  raw[0x70]);
    set_btn("KEY_F2",  raw[0x71]);
    set_btn("KEY_F3",  raw[0x72]);
    set_btn("KEY_F4",  raw[0x73]);
    set_btn("KEY_F5",  raw[0x74]);
    set_btn("KEY_F6",  raw[0x75]);
    set_btn("KEY_F7",  raw[0x76]);
    set_btn("KEY_F8",  raw[0x77]);
    set_btn("KEY_F9",  raw[0x78]);
    set_btn("KEY_F10", raw[0x79]);
    set_btn("KEY_F11", raw[0x7A]);
    set_btn("KEY_F12", raw[0x7B]);

    // Lock keys
    set_btn("KEY_NUMLOCK",    raw[0x90]);
    set_btn("KEY_SCROLLLOCK", raw[0x91]);

    // Modifier keys (sided)
    set_btn("KEY_LSHIFT", raw[0xA0]);
    set_btn("KEY_RSHIFT", raw[0xA1]);
    set_btn("KEY_LCTRL",  raw[0xA2]);
    set_btn("KEY_RCTRL",  raw[0xA3]);
    set_btn("KEY_LALT",   raw[0xA4]);
    set_btn("KEY_RALT",   raw[0xA5]);

    // OEM / punctuation
    set_btn("KEY_SEMICOLON",  raw[0xBA]);
    set_btn("KEY_EQUALS",     raw[0xBB]);
    set_btn("KEY_COMMA",      raw[0xBC]);
    set_btn("KEY_MINUS",      raw[0xBD]);
    set_btn("KEY_PERIOD",     raw[0xBE]);
    set_btn("KEY_SLASH",      raw[0xBF]);
    set_btn("KEY_GRAVE",      raw[0xC0]);
    set_btn("KEY_LBRACKET",   raw[0xDB]);
    set_btn("KEY_BACKSLASH",  raw[0xDC]);
    set_btn("KEY_RBRACKET",   raw[0xDD]);
    set_btn("KEY_APOSTROPHE", raw[0xDE]);
};
