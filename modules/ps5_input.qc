// PlayStation 5 DualSense (via USB) input module

string MODULE_ID      = "ps5_input";
string MODULE_NAME    = "PlayStation 5 DualSense (USB)";
string MODULE_VERSION = "2.0.0";
string MODULE_AUTHOR  = "MobCat";
int    ENGINE_VERSION = 2;
int    VID            = 0x054C;
int    PID            = 0x0CE6;
string DRIVER         = "hid_input";

void() declare_signals =
{
    // Output report size
    // DualSense USB output report 0x02 64 bytes total.
    feedback_len(64);

    // Feedback signals (output to the controller)
    // Rumble motors
    feedback("RUMBLE_HEAVY", 0, 255);   // left motor  (low-freq, strong)
    feedback("RUMBLE_SOFT",  0, 255);   // right motor (high-freq, soft)
    // Light bar RGB
    feedback("LED_R", 0, 255);
    feedback("LED_G", 0, 255);
    feedback("LED_B", 0, 255);
    // Mic button LED: 0=off, 1=on, 2=pulse. Pulse rate set by controler.
    feedback("MIC_LED", 0, 2);
    // Player indicator LEDs (the 5 dots)
    feedback("LED_P_OUTER",  0, 1);  // both outer dots  (bits 4+0 = 0x11)
    feedback("LED_P_INNER",  0, 1);  // both inner dots  (bits 3+1 = 0x0A)
    feedback("LED_P_CENTRE", 0, 1);  // centre dot only  (bit  2   = 0x04)

    // Input signals (data from the controller)
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

    axis("LEFT_STICK_X",  0, 255);
    axis("LEFT_STICK_Y",  0, 255);
    axis("RIGHT_STICK_X", 0, 255);
    axis("RIGHT_STICK_Y", 0, 255);
    axis("L2_ANALOG",     0, 255);
    axis("R2_ANALOG",     0, 255);
    axis("TOUCH1_X",      0, 1919);
    axis("TOUCH1_Y",      0, 1079);
    axis("TOUCH2_X",      0, 1919);
    axis("TOUCH2_Y",      0, 1079);
};

void(bytes raw) parse =
{
    // Sticks and triggers (bytes 1-6)
    set_axis("LEFT_STICK_X",  raw[1]);
    set_axis("LEFT_STICK_Y",  raw[2]);
    set_axis("RIGHT_STICK_X", raw[3]);
    set_axis("RIGHT_STICK_Y", raw[4]);
    set_axis("L2_ANALOG",     raw[5]);
    set_axis("R2_ANALOG",     raw[6]);

    // D-pad: byte 8 low nibble, 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW, 8=neutral
    local int dpad = raw[8] & 0x0F;
    set_btn("BTN_DPAD_UP",    dpad == 0 || dpad == 1 || dpad == 7);
    set_btn("BTN_DPAD_RIGHT", dpad == 1 || dpad == 2 || dpad == 3);
    set_btn("BTN_DPAD_DOWN",  dpad == 3 || dpad == 4 || dpad == 5);
    set_btn("BTN_DPAD_LEFT",  dpad == 5 || dpad == 6 || dpad == 7);

    // Face buttons: byte 8 high nibble
    set_btn("BTN_SQUARE",   raw[8] & 0x10);
    set_btn("BTN_CROSS",    raw[8] & 0x20);
    set_btn("BTN_CIRCLE",   raw[8] & 0x40);
    set_btn("BTN_TRIANGLE", raw[8] & 0x80);

    // Shoulder buttons + system: byte 9
    set_btn("BTN_L1",      raw[9] & 0x01);
    set_btn("BTN_R1",      raw[9] & 0x02);
    set_btn("BTN_L2",      raw[9] & 0x04);
    set_btn("BTN_R2",      raw[9] & 0x08);
    set_btn("BTN_CREATE",  raw[9] & 0x10);
    set_btn("BTN_OPTIONS", raw[9] & 0x20);
    set_btn("BTN_L3",      raw[9] & 0x40);
    set_btn("BTN_R3",      raw[9] & 0x80);

    // byte 10
    set_btn("BTN_PS",       raw[10] & 0x01);
    set_btn("BTN_TOUCHPAD", raw[10] & 0x02);
    set_btn("BTN_MUTE",     raw[10] & 0x04);

    // Touchpad finger 1: bytes 33-36
    // Byte 33 bit 7 = finger active (0=active, 1=not touching)
    // Bytes 33-35 encode X (12 bits) and Y (12 bits)
    local int t1_raw0 = raw[33];
    local int t1_raw1 = raw[34];
    local int t1_raw2 = raw[35];
    local int touch1_x = t1_raw1 | ((t1_raw2 & 0x0F) << 8);
    local int touch1_y = (t1_raw2 >> 4) | (raw[36] << 4);
    set_axis("TOUCH1_X", touch1_x);
    set_axis("TOUCH1_Y", touch1_y);

    // Touchpad finger 2: bytes 37-40
    local int t2_raw0 = raw[37];
    local int t2_raw1 = raw[38];
    local int t2_raw2 = raw[39];
    local int touch2_x = t2_raw1 | ((t2_raw2 & 0x0F) << 8);
    local int touch2_y = (t2_raw2 >> 4) | (raw[40] << 4);
    set_axis("TOUCH2_X", touch2_x);
    set_axis("TOUCH2_Y", touch2_y);
};

void() write_feedback =
{
    set_feedback_byte(0, 0x02);  // Report ID
    // Byte 1 (valid_flag0):
    //   0x01 = DS_OUTPUT_VALID_FLAG0_COMPATIBLE_VIBRATION enable rumble emulation
    //   0x02 = DS_OUTPUT_VALID_FLAG0_HAPTICS_SELECT drive actuators in rumble mode
    //   Both bits must be set together for the physical actuators to rumble.
    //   Using 0xFF sets audio flags (bits 5-7) which conflicts with rumble emulation.
    //   Source: Linux kernel hid-playstation.c, pydualsense, dualsensectl
    set_feedback_byte(1, 0x03);
    // Byte 2 (valid_flag1):
    //   0x01 = mic mute LED control
    //   0x04 = lightbar RGB control
    //   0x10 = player indicator LED control
    set_feedback_byte(2, 0x15);

    // Rumble motors. Both bits in byte 1 must be set (0x03) for these to reach
    // the physical actuators. Byte 3 = right/high-freq, byte 4 = left/low-freq.
    set_feedback_byte(3, get_feedback("RUMBLE_SOFT"));
    set_feedback_byte(4, get_feedback("RUMBLE_HEAVY"));

    // Mic button LED
    set_feedback_byte(9, get_feedback("MIC_LED"));

    // Player LED brightness. Always high (0 = brightest)
    set_feedback_byte(38, 0);

    // Player LED bitmask
    // Player 1 = LED_P_CENTRE
    // Player 2 = LED_P_OUTER
    // Player 3 = LED_P_OUTER + LED_P_CENTRE
    // Player 4 = LED_P_OUTER + LED_P_INNER
    local int leds = 0;
    if (get_feedback("LED_P_OUTER"))  { leds = leds | 0x11; }
    if (get_feedback("LED_P_INNER"))  { leds = leds | 0x0A; }
    if (get_feedback("LED_P_CENTRE")) { leds = leds | 0x04; }
    set_feedback_byte(44, leds);

    // Light bar colour
    set_feedback_byte(45, get_feedback("LED_R"));
    set_feedback_byte(46, get_feedback("LED_G"));
    set_feedback_byte(47, get_feedback("LED_B"));
};
