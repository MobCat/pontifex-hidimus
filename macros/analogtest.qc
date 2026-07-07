// Phidimus gentle exerciser — macro module (Engine 4.2).
//
// The console-SAFE counterpart to x360testpatten: mostly analog (both sticks,
// both triggers) plus ONE deliberate digital input — the shoulder buttons —
// so the test proves the digital path too without being all-analog. It
// deliberately touches NO "dangerous" digital buttons: no face buttons, no
// Start/Back, no d-pad, no stick clicks. This matters on a REAL console: the
// full x360testpatten sweep cycles Back while the triggers ramp, and
// LT+RT+Back is a reboot combo on the original Xbox, so it resets the machine
// mid-test. The shoulders are safe — on an Xbox 360→OG Xbox mapping the digital
// bumpers map to the Black/White face buttons, nowhere near a reset combo. This
// macro can be left running on hardware indefinitely.
//
// Everything moves SLOWLY (multi-second cycles) so you can watch each control
// settle in a dashboard/test menu instead of a blur.
//
// Functions (compose them on one [defaults] line; they drive disjoint signals):
//   lstick()    — left stick traces a slow circle.
//   rstick()    — right stick traces a slow circle the other way.
//   triggers()  — LT / RT slow triangle ramp, opposing each other.
//   shoulders() — BTN_LB / BTN_RB DIGITAL bumpers, pressed alternately (never
//                 together). A digital source → any analog target (e.g. OG Xbox
//                 White/Black) cross-maps to a full 255 press in the config.
//
// Integer math only: now_ms() is integer and the circle uses a 16-point cosine
// LOOKUP interpolated between points — no float lib, no trig (same as
// x360testpatten). Signal names match x360testpatten so configs stay familiar.
//
//	[defaults]
//	macro = analogtest.lstick(), analogtest.rstick(), analogtest.triggers(), analogtest.shoulders()

string MODULE_ID      = "analogtest";
string MODULE_NAME    = "Phidimus Gentle Analog Exerciser";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.3.0";
string DRIVER         = "macro";

// Full-scale stick amplitude (just inside the ±32767 range).
int STICK_AMP = 32000;

void() declare_signals =
{
    // Sticks (signed, centred 0) and the analog controls (unsigned, rest 0).
    axis("LX", -32768, 32767);
    axis("LY", -32768, 32767);
    axis("RX", -32768, 32767);
    axis("RY", -32768, 32767);
    axis("LT", 0, 255);
    axis("RT", 0, 255);

    // Digital shoulder bumpers — the one non-analog input in this test. On an
    // Xbox 360→OG Xbox config these map to the (analog) White/Black buttons; a
    // digital→analog cross-map presses them fully (255).
    btn("BTN_LB");
    btn("BTN_RB");
};

// ── cosine lookup (no float / trig) ────────────────────────────────────────────

// costab(i) → cos(i * 22.5°) scaled to ±STICK_AMP, for i taken modulo 16.
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
// frac/256, so the circle moves smoothly instead of stepping.
int(int idx, int frac) cosi =
{
    local int a = costab(idx);
    local int b = costab(idx + 1);
    return a + ((b - a) * frac) / 256;
};

// circleXY(revMs, phaseOff) drives a smooth circle: returns nothing but the
// callers below inline the same math with different signals/direction, so this
// is kept as a note rather than a helper (QC has no multi-return).

// ── test functions ─────────────────────────────────────────────────────────────

// lstick() sweeps the left stick around the rim once every 4 s.
void() lstick =
{
    local int revMs = 4000;                          // one slow revolution
    local int p     = now_ms() % revMs;
    local int units = p * (16 * 256) / revMs;        // 0 .. 4096
    local int idx   = (units / 256) & 15;
    local int frac  = units % 256;

    set_axis("LX", cosi(idx, frac));                 // x = cos(theta)
    set_axis("LY", cosi(idx + 12, frac));            // y = cos(theta - 90) = sin(theta)
};

// rstick() sweeps the right stick around the rim the OTHER way, once every 5 s
// (a different period so the two sticks visibly drift out of phase).
void() rstick =
{
    local int revMs = 5000;
    local int p     = revMs - (now_ms() % revMs);    // reversed → opposite spin
    local int units = p * (16 * 256) / revMs;
    local int idx   = (units / 256) & 15;
    local int frac  = units % 256;

    set_axis("RX", cosi(idx, frac));
    set_axis("RY", cosi(idx + 12, frac));
};

// triggers() ramps LT 0..255..0 (slow triangle) with RT as its complement, so
// the two analog triggers oppose each other over a 3 s cycle.
void() triggers =
{
    local int period = 3000;
    local int ramp = (now_ms() % period) * 2;             // 0 .. 2*period
    if (ramp > period) { ramp = (period * 2) - ramp; }     // fold to triangle
    local int lt = (ramp * 255) / period;                  // 0 .. 255
    set_axis("LT", lt);
    set_axis("RT", 255 - lt);
};

// shoulders() presses the two DIGITAL bumpers alternately on a 3 s cycle —
// BTN_LB for the first half, BTN_RB for the second — so they never overlap and
// each is a clean, visible on/off press.
void() shoulders =
{
    local int period = 3000;
    local int t = now_ms() % period;
    set_btn("BTN_LB", t <  (period / 2));
    set_btn("BTN_RB", t >= (period / 2));
};
