// Analog face buttons — latching macro (Engine 4.2).
//
// Gives a controller with DIGITAL face buttons (e.g. a DualSense) access to the
// ANALOG face buttons of a target that has them (e.g. the original Xbox, where
// A/B/X/Y report 0-255 of pressure). A latching toggle (the DualSense mute
// button) arms the feature; the mic-mute LED signals the state.
//
//   Disarmed (mic LED off) — face buttons behave normally: held = full press
//     (255), released = 0. The right trigger passes through normally.
//   Armed (mic LED on)     — while you HOLD a face button, the RIGHT TRIGGER's
//     analog value sets that button's pressure (so you can feather it). The
//     trigger is "consumed" while dialing, so it does NOT also fire the output
//     trigger. Release the face button and the trigger works normally again.
//     While actively dialing (face held + trigger pulled) the mic LED pulses.
//
// The macro OWNS the face outputs and the right trigger: the config maps its
// AF_* signals to the target, and must NOT also map the raw face buttons /
// right trigger to the same outputs (that would double-drive them).
//
//	[defaults]
//	macro = analogface.update()          ; run every tick
//
//	[analogface.macro]
//	BTN_MUTE:press = toggle()             ; press to arm / disarm (latching)
//
//	[<output>.axes]
//	AF_A  = BTN_A                         ; analog face outputs
//	AF_B  = BTN_B
//	AF_X  = BTN_X
//	AF_Y  = BTN_Y
//	!BTN_PS+AF_RT = RIGHT_TRIGGER         ; gated right trigger (see the config)
//
//	[<input>.feedback]
//	MIC_LED = AF_LED                      ; 0 off / 1 on / 2 pulse
//
// Reads the input signals BTN_CROSS/CIRCLE/SQUARE/TRIANGLE and R2_ANALOG by name
// (DualSense). To retarget it to another input, change those names below.

string MODULE_ID      = "analogface";
string MODULE_NAME    = "Analog Face Buttons";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.3.0";
string DRIVER         = "macro";

// Latch state, toggled by toggle(). Persists across frames.
int armed = 0;

void() declare_signals =
{
    // Analog face outputs (0-255) the config maps to the target's face buttons.
    axis("AF_A", 0, 255);
    axis("AF_B", 0, 255);
    axis("AF_X", 0, 255);
    axis("AF_Y", 0, 255);

    // Gated right trigger (0-255): the value the config should send to the
    // output's right trigger — the raw trigger normally, or 0 while it is being
    // used to dial a face button's pressure.
    axis("AF_RT", 0, 255);

    // Mic-mute LED state: 0 = off (disarmed), 1 = on (armed, idle), 2 = pulse
    // (armed and actively dialing a face button).
    axis("AF_LED", 0, 2);
};

// toggle() — bind to a latch button's press edge (BTN_MUTE:press). Flips armed.
void() toggle =
{
    armed = 1 - armed;
};

// oneFace(held, out, r2) drives one analog face output and returns 1 if the
// button is held. Armed + held → analog value = the trigger; disarmed + held →
// full press (255); not held → 0.
int(int held, string out, int r2) oneFace =
{
    if (held)
    {
        if (armed) { set_axis(out, r2); }
        else       { set_axis(out, 255); }
        return 1;
    }
    set_axis(out, 0);
    return 0;
};

// update() — bind always-on in [defaults]. Runs the whole feature each tick.
void() update =
{
    local int r2 = get_signal("R2_ANALOG");

    local int anyHeld = 0;
    anyHeld = anyHeld + oneFace(get_signal("BTN_CROSS"),    "AF_A", r2);
    anyHeld = anyHeld + oneFace(get_signal("BTN_CIRCLE"),   "AF_B", r2);
    anyHeld = anyHeld + oneFace(get_signal("BTN_SQUARE"),   "AF_X", r2);
    anyHeld = anyHeld + oneFace(get_signal("BTN_TRIANGLE"), "AF_Y", r2);

    // Right trigger: consumed (0) while armed and dialing a face button, so it
    // drives face pressure instead of the output trigger; otherwise passthrough.
    if (armed && anyHeld) { set_axis("AF_RT", 0); }
    else                  { set_axis("AF_RT", r2); }

    // Mic LED: off disarmed; pulse while actively dialing (armed + face held +
    // trigger pulled); solid on when armed and idle.
    if (armed)
    {
        if (anyHeld && (r2 > 0)) { set_axis("AF_LED", 2); }
        else                     { set_axis("AF_LED", 1); }
    }
    else
    {
        set_axis("AF_LED", 0);
    }
};
