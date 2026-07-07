// Phidimus self-test pattern — macro module (Engine 4.1).
//
// A scriptable signal source: it ignores any physical input and synthesises a
// moving pattern on the signal bus, so a virtual pad visibly exercises without a
// controller plugged in. Replaces the old hard-coded gadgettest / usbiptest
// binaries — to change the test you edit this file or swap the macro, no recompile.
//
// Two functions, driving DISJOINT signals so they can run alone or together:
//   sweep() — both analog sticks sweep, both triggers ramp, 16 buttons cycle.
//   dpad()  — the 8-way hat / D-pad walks through its directions.
//
// Run one, or both at once, from a config's [defaults] line (see
// config/testpad_selftest.ini):
//
//	[defaults]
//	macro = testpattern.sweep(), testpattern.dpad()   ; exercise the whole pad
//
// Adding a test is just another function here — no recompile.

string MODULE_ID      = "testpattern";
string MODULE_NAME    = "Phidimus Self-Test Pattern";
string MODULE_VERSION = "1.1.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.1.0";
string DRIVER         = "macro";

void() declare_signals =
{
    // Signal names the macro produces; merged into the input namespace so a config
    // maps them onto an output like any real controller signal.
    axis("STICK_X",  -127, 127);
    axis("STICK_Y",  -127, 127);
    axis("STICK_RX", -127, 127);
    axis("STICK_RY", -127, 127);
    axis("TRIGGER_L", 0, 255);
    axis("TRIGGER_R", 0, 255);

    btn("BTN_1");  btn("BTN_2");  btn("BTN_3");  btn("BTN_4");
    btn("BTN_5");  btn("BTN_6");  btn("BTN_7");  btn("BTN_8");
    btn("BTN_9");  btn("BTN_10"); btn("BTN_11"); btn("BTN_12");
    btn("BTN_13"); btn("BTN_14"); btn("BTN_15"); btn("BTN_16");

    btn("HAT_UP");
    btn("HAT_DOWN");
    btn("HAT_LEFT");
    btn("HAT_RIGHT");
};

// tristick(t, period) → a 0..1..0 fold of t over period, scaled to -120..+120.
// Pure integer math (now_ms() is integer); no float lib needed.
int(int t, int period) tristick =
{
    local int ramp = (t % period) * 2;     // 0 .. 2*period
    if (ramp > period)
    {
        ramp = (period * 2) - ramp;        // fold into a 0..period triangle
    }
    return (ramp * 240) / period - 120;    // -120 .. +120
};

// sweep() runs every tick: analog sticks + triggers + a 16-button cycle.
void() sweep =
{
    local int t = now_ms();
    local int period = 2000;

    // Left stick sweeps; right stick is the same sweep half a period out of phase,
    // so the two sticks visibly move differently.
    local int xl = tristick(t, period);
    set_axis("STICK_X", xl);
    set_axis("STICK_Y", 0 - xl);

    local int xr = tristick(t + (period / 2), period);
    set_axis("STICK_RX", xr);
    set_axis("STICK_RY", 0 - xr);

    // Triggers ramp 0..255 (sawtooth), the right one offset so both move.
    set_axis("TRIGGER_L", ((t % period) * 255) / period);
    set_axis("TRIGGER_R", (((t + (period / 2)) % period) * 255) / period);

    // One of sixteen buttons at a time, advancing every 150 ms.
    local int idx = (t / 150) % 16;
    set_btn("BTN_1",  idx == 0);  set_btn("BTN_2",  idx == 1);
    set_btn("BTN_3",  idx == 2);  set_btn("BTN_4",  idx == 3);
    set_btn("BTN_5",  idx == 4);  set_btn("BTN_6",  idx == 5);
    set_btn("BTN_7",  idx == 6);  set_btn("BTN_8",  idx == 7);
    set_btn("BTN_9",  idx == 8);  set_btn("BTN_10", idx == 9);
    set_btn("BTN_11", idx == 10); set_btn("BTN_12", idx == 11);
    set_btn("BTN_13", idx == 12); set_btn("BTN_14", idx == 13);
    set_btn("BTN_15", idx == 14); set_btn("BTN_16", idx == 15);
};

// dpad() walks the hat through its eight directions, ~400 ms each, looping. It
// drives the four HAT_* direction signals (the output module folds them into a
// real hat). Each direction button is the sum of the idx values that include it
// (a "+" of comparisons stands in for an OR), e.g. UP is active at N, NE, NW.
void() dpad =
{
    local int idx = (now_ms() / 400) % 8;   // 0..7: N NE E SE S SW W NW
    set_btn("HAT_UP",    (idx == 0) + (idx == 1) + (idx == 7));
    set_btn("HAT_RIGHT", (idx == 1) + (idx == 2) + (idx == 3));
    set_btn("HAT_DOWN",  (idx == 3) + (idx == 4) + (idx == 5));
    set_btn("HAT_LEFT",  (idx == 5) + (idx == 6) + (idx == 7));
};
