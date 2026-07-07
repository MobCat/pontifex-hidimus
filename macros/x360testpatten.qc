// Phidimus Xbox 360 self-test pattern — macro module (Engine 4.1).
//
// The bigger sibling of testpattern.qc: it exercises the FULL Xbox 360 control
// set so a real virtual xbox360_usb pad can be verified end-to-end with no
// physical controller. Drives its own named signals; config/xbox360_selftest.ini
// wires them onto the XINPUT_* outputs.
//
// Functions (run together from a config [defaults] line; they touch DISJOINT
// signals so they compose):
//   buttons()  — cycle the 11 non-dpad buttons one at a time (face, bumpers,
//                stick-press, Start/Back/Guide).
//   dpad()     — walk the 8-way D-pad (N NE E SE S SW W NW) like testpattern.
//   lstick()   — left stick: opposing X/Y sweep, 5 cycles one diagonal then 5
//                the other (an X over time).
//   rstick()   — right stick: a smooth circle around the rim, 5 revolutions one
//                way then 5 the other.
//   triggers() — LT / RT ramp 0..255..0, opposing each other.
//
// Everything is integer math: now_ms() is integer, and the circle uses a 16-point
// cosine LOOKUP (costab) interpolated between points — no float lib, no trig.
//
//	[defaults]
//	macro = x360testpatten.buttons(), x360testpatten.dpad(), x360testpatten.lstick(), x360testpatten.rstick(), x360testpatten.triggers()

string MODULE_ID      = "x360testpatten";
string MODULE_NAME    = "Phidimus Xbox 360 Self-Test Pattern";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.1.0";
string DRIVER         = "macro";

// Full-scale stick amplitude (just inside the ±32767 XInput range).
int STICK_AMP = 32000;

void() declare_signals =
{
    // Signal names this macro produces; merged into the input namespace so the
    // config maps them onto xbox360_usb like any real controller signal.

    // Face + bumpers + stick-press + menu (the 11 buttons buttons() cycles).
    btn("BTN_A");  btn("BTN_B");  btn("BTN_X");  btn("BTN_Y");
    btn("BTN_LB"); btn("BTN_RB"); btn("BTN_LS"); btn("BTN_RS");
    btn("BTN_START"); btn("BTN_BACK");
    btn("BTN_GUIDE");

    // D-pad as four direction signals (dpad() folds the 8-way walk into these).
    btn("DPAD_UP"); btn("DPAD_DOWN"); btn("DPAD_LEFT"); btn("DPAD_RIGHT");

    // Sticks (signed, centred 0) and triggers (unsigned, rest 0) — same ranges as
    // the xbox360_usb output, so the config maps them straight through.
    axis("LX", -32768, 32767);
    axis("LY", -32768, 32767);
    axis("RX", -32768, 32767);
    axis("RY", -32768, 32767);
    axis("LT", 0, 255);
    axis("RT", 0, 255);
};

// ── cosine lookup (no float / trig) ────────────────────────────────────────────

// costab(i) → cos(i * 22.5°) scaled to ±STICK_AMP, for i taken modulo 16. A
// 16-point quarter-degree table; the four cardinals are exact 0 / ±32000.
int(int i) costab =
{
    local int k = i & 15;            // wrap to 0..15
    if (k == 0)  { return  32000; }
    if (k == 1)  { return  29564; }
    if (k == 2)  { return  22627; }
    if (k == 3)  { return  12246; }
    if (k == 4)  { return      0; }
    if (k == 5)  { return -12246; }
    if (k == 6)  { return -22627; }
    if (k == 7)  { return -29564; }
    if (k == 8)  { return -32000; }
    if (k == 9)  { return -29564; }
    if (k == 10) { return -22627; }
    if (k == 11) { return -12246; }
    if (k == 12) { return      0; }
    if (k == 13) { return  12246; }
    if (k == 14) { return  22627; }
    return 29564;                    // k == 15
};

// cosi(idx, frac) → costab linearly interpolated between idx and idx+1 by
// frac/256, so the 16-point circle moves smoothly instead of stepping.
int(int idx, int frac) cosi =
{
    local int a = costab(idx);
    local int b = costab(idx + 1);
    return a + ((b - a) * frac) / 256;
};

// ── test functions ─────────────────────────────────────────────────────────────

// buttons() cycles the 11 non-dpad buttons, one at a time, advancing every 250 ms.
void() buttons =
{
    local int idx = (now_ms() / 250) % 11;
    set_btn("BTN_A",     idx == 0);
    set_btn("BTN_B",     idx == 1);
    set_btn("BTN_X",     idx == 2);
    set_btn("BTN_Y",     idx == 3);
    set_btn("BTN_LB",    idx == 4);
    set_btn("BTN_RB",    idx == 5);
    set_btn("BTN_LS",    idx == 6);
    set_btn("BTN_RS",    idx == 7);
    set_btn("BTN_START", idx == 8);
    set_btn("BTN_BACK",  idx == 9);
    //set_btn("BTN_GUIDE", idx == 10);
};

// dpad() walks the hat through its eight directions, ~400 ms each, looping. Each
// direction button is the sum of the idx values that include it (a "+" of
// comparisons stands in for an OR), e.g. UP is active at N, NE, NW.
void() dpad =
{
    local int idx = (now_ms() / 400) % 8;   // 0..7: N NE E SE S SW W NW
    set_btn("DPAD_UP",    (idx == 0) + (idx == 1) + (idx == 7));
    set_btn("DPAD_RIGHT", (idx == 1) + (idx == 2) + (idx == 3));
    set_btn("DPAD_DOWN",  (idx == 3) + (idx == 4) + (idx == 5));
    set_btn("DPAD_LEFT",  (idx == 5) + (idx == 6) + (idx == 7));
};

// lstick() sweeps the left stick along a diagonal (opposing X/Y), 5 out-and-back
// cycles on one diagonal then 5 on the other — tracing an X over time.
void() lstick =
{
    local int period = 1500;            // one out-and-back cycle
    local int dir    = period * 5;      // 5 cycles per diagonal
    local int t      = now_ms() % (dir * 2);

    // Triangle value s in -AMP..+AMP from the per-cycle phase.
    local int ramp = (t % period) * 2;                 // 0 .. 2*period
    if (ramp > period) { ramp = (period * 2) - ramp; }  // fold to a 0..period triangle
    local int s = (ramp * (STICK_AMP * 2)) / period - STICK_AMP;

    set_axis("LX", s);
    if (t < dir)
    {
        set_axis("LY", 0 - s);          // anti-diagonal "\" for 5 cycles
    }
    else
    {
        set_axis("LY", s);              // main diagonal "/" for the next 5
    }
};

// rstick() drives the right stick in a smooth circle around the rim: 5 full
// revolutions one way, then 5 the other.
void() rstick =
{
    local int revMs = 2500;             // one full revolution
    local int dirMs = revMs * 5;        // 5 revolutions per direction
    local int t     = now_ms() % (dirMs * 2);

    // Phase within the current direction; the second half mirrors time so the
    // circle reverses (clockwise vs counter-clockwise).
    local int p;
    if (t < dirMs) { p = t; }
    else           { p = (dirMs * 2) - t; }

    // Map the phase to 16 steps × 256 sub-step units per revolution.
    local int units = (p % revMs) * (16 * 256) / revMs;  // 0 .. 4096
    local int idx   = (units / 256) & 15;
    local int frac  = units % 256;

    set_axis("RX", cosi(idx, frac));        // x = cos(theta)
    set_axis("RY", cosi(idx + 12, frac));   // y = cos(theta - 90) = sin(theta)
};

// triggers() ramps LT 0..255..0 (triangle) with RT as its complement, so the two
// analog triggers oppose each other.
void() triggers =
{
    local int period = 1200;
    local int ramp = (now_ms() % period) * 2;            // 0 .. 2*period
    if (ramp > period) { ramp = (period * 2) - ramp; }    // fold to triangle
    local int lt = (ramp * 255) / period;                 // 0 .. 255
    set_axis("LT", lt);
    set_axis("RT", 255 - lt);
};
