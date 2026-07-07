// Rapid fire — macro module (Engine 4.1).
//
// A generic, latching auto-fire. While "armed", holding a bound button makes the
// engine pulse that button on/off instead of sending a steady hold — so a single
// hold becomes a stream of presses. A latch button toggles arming on/off, and an
// optional status LED signals the state to the user.
//
// Nothing here is device-specific: the macro acts on whatever buttons the config
// binds, and drives a generic RF_LED signal the config can route to any LED. It
// works with any input module that exposes the bound buttons.
//
// Wiring (see config/ps5_to_xbox360.ini). The latch toggles on the *press* edge;
// each face button rapid-fires while held; the LED is optional:
//
//	[defaults]
//	macro = rapidfire.led()              ; status LED (omit this line for no LED)
//
//	[rapidfire.macro]
//	BTN_MUTE:press = toggle()            ; press to arm / disarm (latching)
//	BTN_CROSS      = fire()              ; hold to auto-fire at the default rate
//	BTN_CIRCLE     = fire()
//	BTN_SQUARE     = fire(20)            ; or pick a per-button rate (Hz)
//	BTN_TRIANGLE   = fire(20)
//
//	[ps5ds.feedback]
//	MIC_LED = RF_LED                     ; route the status LED to the mic-mute LED
//
// Off → buttons behave normally. Armed + idle → LED solid. Armed + firing → LED
// blinks in time with the shots. latch / LED / Hz are all optional and configurable.

string MODULE_ID      = "rapidfire";
string MODULE_NAME    = "Rapid Fire";
string MODULE_VERSION = "1.0.0";
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.1.0";
string DRIVER         = "macro";

// Default fire rate (Hz) when fire() is called with no argument. Editable here;
// any fire() call may override it, e.g. fire(20).
int RF_HZ = 12;

// armed is the latch state, toggled by toggle(). Persists across frames.
int armed = 0;

void() declare_signals =
{
    // Generic status-LED signal (0 = off, 1 = on). The config routes it to a real
    // device LED via a [<input>.feedback] map — or leaves it unrouted for no LED.
    axis("RF_LED", 0, 1);
};

// toggle() — bind to a latch button's press edge (e.g. BTN_MUTE:press). Flips the
// armed state once per press.
void() toggle =
{
    armed = 1 - armed;
};

// led() — bind always-on in [defaults]. Holds the status LED at its baseline:
// solid while armed, off otherwise. fire() overrides it to blink while shooting,
// so led() must run first (always-on calls run before the [rapidfire.macro] ones).
void() led =
{
    set_axis("RF_LED", armed);
};

// fire(hz) — bind to a button (level trigger). While armed and the button is held,
// pulse it at hz (or RF_HZ when hz is omitted/0): on for the first half of each
// period, off for the second. Blinks the LED in time with the shots. When not
// armed it does nothing, so the held button passes through normally.
void(int hz) fire =
{
    if (armed)
    {
        local int h = hz;
        if (h <= 0) { h = RF_HZ; }
        local int period = 1000 / h;
        local int on = 0;
        if ((now_ms() % period) * 2 < period) { on = 1; }

        set_btn(trigger(), on);     // override the held button with the pulse
        set_axis("RF_LED", on);     // blink the status LED with the firing
    }
};
