// Output self-test — macro module (Engine 4.1).
//
// Drives the DualSense's *internal* feedback channels from controller inputs so
// the whole output path (player LEDs, lightbar RGB + brightness) can be exercised
// by hand, with no game running. Pairs with
// config/pc/ps5_bt_to_usb_fulltest.ini.
//
//   L1 / R1          step the player-LED combo (prev / next)
//   BTN_TOUCHPAD     cycle the lightbar brightness
//   TOUCH1 + TOUCH2  (both fingers down) set the lightbar RGB from the two points
//
// L2 / R2 → left / right rumble is a pure 1:1 passthrough, so it lives in the
// config as a [ps5ds.feedback] map (declarative data, not macro logic) — see the
// fulltest .ini. Every bound input ALSO still passes through to the host via the
// [ps5_usb.*] sections, so this is additive: pressing L1 cycles the LEDs *and*
// sends BTN_L1 to the host.
//
// Pattern (important): the merged signal bus is rebuilt every frame, so a feedback
// signal must be re-asserted every frame or it falls back to 0. apply() therefore
// holds ALL output and is bound always-on in [defaults]; the edge functions
// (next/prev/brightness, bound to a button :press) only mutate stored state.

string MODULE_ID      = "outtest";
string MODULE_NAME    = "Output Self-Test";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.1.0";
string DRIVER         = "macro";

// Player-LED combo cycle: index into a 5-step table of OUTER/INNER/CENTRE.
int pled_idx   = 0;
int PLED_COUNT = 5;

// Lightbar brightness cycle: 0 = full, 1 = two-thirds, 2 = one-third. The
// DualSense lightbar has no brightness register — brightness IS the RGB
// magnitude — so we scale the chosen colour by this fraction.
int bright_idx = 0;

// Last lightbar colour picked by a two-finger touch (held until the next touch).
// Start on a mid grey so the bar is visibly "on, under our control" before the
// first touch.
int lb_r = 96;
int lb_g = 96;
int lb_b = 96;

// Touch rest position reported by ps5ds.qc when a finger is NOT down. We have no
// explicit touch-active signal on the bus, so "coordinate away from rest" is our
// stand-in for "finger down" (good enough for a bench test).
int TOUCH_REST_X = 960;
int TOUCH_REST_Y = 540;

void() declare_signals =
{
    // Player-LED pair signals (0/1) — routed to LED_P_* in the config.
    axis("PLED_OUTER",  0, 1);
    axis("PLED_INNER",  0, 1);
    axis("PLED_CENTRE", 0, 1);

    // Lightbar RGB (0..255) after brightness scaling — routed to LED_R/G/B.
    axis("LB_R", 0, 255);
    axis("LB_G", 0, 255);
    axis("LB_B", 0, 255);
};

// next() / prev() — bind to BTN_R1:press / BTN_L1:press. Step the combo index.
void() next =
{
    pled_idx = pled_idx + 1;
    if (pled_idx >= PLED_COUNT) { pled_idx = 0; }
};
void() prev =
{
    pled_idx = pled_idx - 1;
    if (pled_idx < 0) { pled_idx = PLED_COUNT - 1; }
};

// brightness() — bind to BTN_TOUCHPAD:press. Cycle full → 2/3 → 1/3 → full.
void() brightness =
{
    bright_idx = bright_idx + 1;
    if (bright_idx > 2) { bright_idx = 0; }
};

// scale255(v, max) — map a 0..max touch coordinate onto 0..255 (clamped).
int(int v, int max) scale255 =
{
    if (v < 0)   { v = 0; }
    if (v > max) { v = max; }
    return (v * 255) / max;
};

// apply() — bind always-on in [defaults]. Re-asserts every output channel each
// frame from the stored state, so feedback stays live.
void() apply =
{
    // ── Player-LED combo ──────────────────────────────────────────────────────
    local int outer  = 0;
    local int inner  = 0;
    local int centre = 0;
    if (pled_idx == 0) { centre = 1; }                        // centre dot
    if (pled_idx == 1) { inner = 1; centre = 1; }             // inner pair + centre
    if (pled_idx == 2) { outer = 1; inner = 1; centre = 1; }  // all five
    if (pled_idx == 3) { outer = 1; }                         // outer pair only
    // pled_idx == 4 → all off
    set_axis("PLED_OUTER",  outer);
    set_axis("PLED_INNER",  inner);
    set_axis("PLED_CENTRE", centre);

    // ── Lightbar colour from a two-finger touch ───────────────────────────────
    // When BOTH fingers are down, recolour the bar: R from finger-1 X, G from
    // finger-1 Y, B from finger-2 X. The colour persists after you lift off.
    local int t1x = get_signal("TOUCH1_X");
    local int t1y = get_signal("TOUCH1_Y");
    local int t2x = get_signal("TOUCH2_X");
    local int t2y = get_signal("TOUCH2_Y");
    local int t1_down = 0;
    local int t2_down = 0;
    if (t1x != TOUCH_REST_X) { t1_down = 1; }
    if (t1y != TOUCH_REST_Y) { t1_down = 1; }
    if (t2x != TOUCH_REST_X) { t2_down = 1; }
    if (t2y != TOUCH_REST_Y) { t2_down = 1; }
    if (t1_down) {
        if (t2_down) {
            lb_r = scale255(t1x, 1919);
            lb_g = scale255(t1y, 1079);
            lb_b = scale255(t2x, 1919);
        }
    }

    // ── Brightness scale (num/3) ──────────────────────────────────────────────
    local int num = 3;
    if (bright_idx == 1) { num = 2; }
    if (bright_idx == 2) { num = 1; }
    set_axis("LB_R", (lb_r * num) / 3);
    set_axis("LB_G", (lb_g * num) / 3);
    set_axis("LB_B", (lb_b * num) / 3);
};
