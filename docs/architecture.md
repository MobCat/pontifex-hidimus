# Phidimus architecture (Engine v4.1.0)

How the pieces fit together, and the mental model behind them.
This is the "why it's shaped this way" doc for module authors and for us.

---

## Ethos

Phidimus is an **engine for converting device inputs to device outputs**
nothing more, nothing less. The way JavaScript, Python, or Flash take a script
and run it through an engine that emits native machine code for the host,
Phidimus takes a controller and runs it through an engine that emits native *device reports* for the host.
Same idea, an on-the-fly engine but for **devices, not code**.

Three moves, one idea tying them together:

1. **Read raw, no middlemen.** Inputs come straight off the wire.
   The common HID layer, or raw USB / Bluetooth bytes, so we never depend on a vendor
   driver existing for your device on your platform.
   An original Xbox controller has no official Windows driver and isn't even a conformant USB device;
   we don't care, we read its bytes raw and "just" work it out.
   *Convert what we have into what we need, without outside help.*

2. **Speak a common, human-readable language.** Raw bytes get decoded into plain
   names a real *person* can read (not just a programmer)
   `BTN_A`, `LEFT_STICK_X` are not opaque API constants. There just words.
   A binding config then ties simple words to simple words:
   `BTN_CROSS = XINPUT_GAMEPAD_A`. The entire middle of the chain is legible to a
   human with a basic text editor. No fancy and bloated CLIs or apps.
   But those exist if you want them.

3. **Write back to native, no shims.** Output modules convert and pack those names into the real
   report bytes of a real USB device. `xbox360_usb` output qc module talks to the real Windows `xusb22.sys` driver *directly*. 
   This is the genuine Xbox 360 controller driver for windows, so the OS sees a **real native controller**,
   not a hooked 3rd party API driver carrying someone else's limitations.
   
   This is why ViGEm is gone since 4.0: It was a Windows-only kernel shim locked
   to the XInput template that relied on updates and signing from 3rd parties.
   Said 3rd parties deprecated the driver and moved on, leaving us "high and dry"
   with the limitations this template imposed. And no easy way to fix them our selves.
   We now own the *whole* USB layer as of 4.0, a layer below a driver shim,
   now so we can be more flexible and accurate with our controller simulation.

### Why the common language matters

Because every stage talks in the same human readable words,
**any stage swaps out without disturbing the others.**

- Windows deprecates the Xbox 360 Controller driver for a new XbOne one?
  Just write a new output module that exposes the same `XINPUT_*` vocabulary,
  every existing binding ini config keeps working, untouched.
  Want the new controllers extra features? Add a second module that layers them
  on top of the old vocabulary and use either.
- A new controller appears? like the Steam Controller?
  Write one input module that decodes it into the same human readable words,
  and every output it could ever drive already works.
  Setup the whole input output chain in a few hours, not a few days.

The common language layer is the pivot.
It turns "support N controllers with bespoke M bridges" for every bespoke part into
**N inputs + M outputs that all interoperate**, swap freely,
and rarely need touching when one end of either side of the chain changes.

### No real ceiling on the output

Because the output side is a **full custom USB stack** we synthesize the descriptors,
not fill in a fixed template.
The virtual device can be *anything the OS understands*:
an Xbox pad, a DualSense that Steam accepts, a keyboard, a mouse, 
a keyboard and mouse at the same time, a Wacom tablet, a native
original-Xbox controller that enumerates and works on a real Xbox.
The engine imposes no limit.
The only question is whether you can describe the device in QuakeC.

### Why QuakeC?
IDK I just thought it be fun.
Most projects that need a easy scripting middle language use lua. 
I have nothing really against lua, just thought QuakeC would be fun.
and we get to use a lot of the benefits from a minimal C environment not available to us in lua.

To be fair, this isn't really stuff lua can't do. 
Modern lua has integers and bit ops, and LuaJIT has an FFI library for calling C code.
It's that QC is shaped like the job we are trying to do here (raw bytes and bits, in and out) *by default*,
and the whole VM is ours: A tiny from-scratch interpreter with no runtime to drag along and cram into a pi and its tiny amount of ram.
A few things that actually earn their keep here:

**It reads like the bytes.** The whole engine is masking and shifting raw report bytes,
and QC is C-flavored, so the code just looks like what it's doing:

```c
set_btn("BTN_LT", raw[3] & 0x40);                  // bit test on a report byte
set_axis("LEFT_STICK_X", (raw[1] + 128) & 0xFF);   // two's-complement -> 0-255
local int on = 0;
if ((now_ms() % period) * 2 < period) { on = 1; }  // int modulo, no float creep
```

`int` is the default number (not a float), `& | ^ << >> %` are built in, and `0x40` is
a first-class literal the exact mental model you're already in when you're staring at
a raw HID report or a USB descriptor.

**Mutable byte buffers, like a `uint8_t buf[N]`.**
A HID report *is* a byte array, so we treat it as one, index it, poke it back:

```c
feedback_len(78);                               // allocate the report buffer
set_feedback_byte(11, get_feedback("MIC_LED")); // write one byte
set_report_byte(2, hat & 0x0F);
```

**Descriptors are just literal bytes.**
USB descriptors get pasted straight from a capture as-is. 
Use captured concatenated byte-string literals, no struct-packing dance needed:
(Capture the reality of real hardware with something like Wireshark, paste it right into our code raw)

```c
usb_config(
    "09 02 22 00 01 01 00 80 32"   // configuration
    "09 04 00 00 01 03 00 00 00"   // interface
);
```

**Typed declarations that read like C prototypes** and document themselves:

```c
void(bytes raw) parse = { ... };
int(int t, int period) tristick = { ... };   // typed params + return
int RF_HZ = 12;                              // typed globals
```

**The VM is ours, and tiny.**
A from scratch interpreter. no GC, no tables / closures / coroutines, no stdlib to sandbox.
That smallness is the point: it's deterministic (no GC pauses) and small enough to carry onto the pi right next to the engine.
Embedding lua means embedding its runtime, GC and C API then trimming it back down to what we actually need.
With QC we built exactly the surface we wanted and nothing else, and own every byte of it from the start.

---

## The flow

```
Physical device -> [input module] -> signals -> [macros] -> [config .ini] -> [output module] -> virtual USB device
                    parse()          (common     tick()      mapping +        pack()            the OS binds its
                                     language)               shift guards                       own real driver
```

Input QC modules **decode** raw device bytes into named signals (the common language).
Macros (optional) **transform** the signal bus on a clock, a stateful/timed stage that 
reads and writes signals between the merge and the mapping.

The config ini **wires** input signal names to output signal names with optional simple transforms.
(deadzone, invert, curve, shift key modifiers)

Output QC modules **pack** signals into the report bytes of a virtual USB device the OS or host device can bind its real driver to.

A v4.0+ output module *is* a USB device. See `QC_USB_API_v4_draft.md`.

---

## Why there's no perceivable lag

All the expensive work happens **once, at boot**. The `.qc` modules get lexed and
parsed into an in-memory program, their `declare_*` run, the config ini is read,
and the mapper is built into flat lookup tables
(a signal name straight to an output bitmask or an axis range)
with every binding checked up front.
That happens one time on load and is never touched again.

After that, the per-frame loop is just **raw bytes in, raw bytes out**:

```
read a raw report -> parse() fills a signal map -> mapper does a few lookups
                  -> pack() writes the output bytes -> send it on
```

Nothing is re-read from disk, nothing is re-parsed or re-compiled, and nothing new is allocated,
the merged signal report and the output buffer are reused every frame.
The actual conversion is a handful of map lookups and bit ops, far less time than the gap between two reports from the device.
(A 250 Hz USB pad sends a new report every 4 ms, The translation is a tiny fraction of that, less then 1 ms.
Average human reaction time is ~200 ms. Not saying you wont feel it, just that it wont impact you in any meaningful way)
So the conversion cost basically disappears next to the controller's own report rate back to the host device.
You're limited by how fast your input device reports and your output is polled, **not** by Phidimus sitting in the middle translating stuff.

Plug it in and it feels wired straight through, because timing wise it nearly is.
The modules and config are a convenience for *you* at author time.
Once they're loaded, they cost effectively nothing to run, every frame after boot is the engine
doing the one simple thing it does, Turning one input device's bytes into another's for the host device to read natively.

---

## The two layers: device vs signals

Every device is understood at two levels, and they map onto two declarations and two SDK tools:

| Layer | QC declaration | SDK tool | Question it answers |
|---|---|---|---|
| **Device** | `declare_usb()` | `--usb` | "Can I even talk to this thing? What is it on the wire?" |
| **Signals** | `declare_signals()` | `--hids` / `--probe` | "What do its bytes *mean* as buttons and axes?" |

You always solve the input device layer first. There's no point decoding signals from
an input device you can't read, or one stuck in a low-resolution compatibility mode. 
(AKA the ps5 controller not in "ps5 mode" or a switch controller not receiving the init command from a switch console)
Once the device is talking properly, then you can decode its data into signals.

- `--usb` is the descriptor/transport view (what `declare_usb` sets up).
- `--hids` is the raw HID report view; `--probe` is the decoded-signal view
  (what `declare_signals` + `parse()`/`pack()` produce).

---

## Transport is separate from device definition

The valuable, reusable part of a module is the **device definition**: descriptors + report packing/parsing.
The **transport** (how those bytes reach the OS) is swappable underneath it:

```
        QC module (descriptors, parse/pack)   <- write once
                       │
        USB device state machine (EP0, URBs)  <- shared Go core
                       │
   ┌───────────────────┼────────────────────┐
 USB/IP loopback   USB/IP over LAN     hardware UDC
 (desktop SDK)     (remote dongle)     (phidimus-pi)
```

The same `xbox360_usb.qc` output module runs on the desktop SDK (via USB/IP to a local virtual port),
across a LAN (one PC serves a controller to another, biproduct of the USB/IP protocol),
and on a Pi gadget, without changing or reconfiguring the module.
Keep the transport interface thin and this stays true.
This is the output-side echo of the ethos: own the raw layer, and the thing above it stops caring how the bytes travel.
No need for a driver api like ViGEm, we are the whole xbox controller now.

---

## Why the descriptor is ours now

ViGEm hardcoded its virtual device strings. At the USB layer **we** set the
device descriptor VID/PID, class, the manufacturer/product strings, serial numbers, device fw string, other official identifiers, etc.
That means we can:

- brand it for fun ("Phidimus Xbox Controller")
- **pass through the real device's identity** so a picky driver or anti-cheat
  has even less to scrutinize. We are a virtual device that reports
  the exact strings, VID/PID, and bcdDevice, everything from real genuine hardware.
- be *any* usb device we want, not just an xbox controller, be *anything*.

This is a capability ViGEm never had.
I don't mean to keep shitting on ViGEmBus. It was super useful and easy to setup in the start of this project
but became a real limitation as soon as we wanted to step just a tiny bit outside of it's hard coded template.
So now it sorta just became an example of why we don't use it now, after I spent like a week ripping it out
after fully integrating it all over this project.

---

## Macros. The stateful/timed stage (as of Phidimus 4.1.0)

A macro is a third module kind (`DRIVER = "macro"`, lives in `macros/`):
a scriptable time-driven signal **source** that runs between the input merge and
the config mapping. Input modules decode hardware to names; the config wires the names.
a macro is the home for anything **stateful or timed** for eg. 
a self-test pattern, rapid-fire, a latch. That is logic, and logic must not live in a static declarative config,
so it lives here as a `.qc` script you can change without the need to recompile the whole Phidimus engine.
And part of the pontifex hidimus ethos, anyone can write a macro script and anyone else can include it into
their binding config independently of each other. For eg re-use the same basic macro script across multiple configs.
Just wire it to what buttons or functions you want in your config.

A macro reads the merged signal bus and writes signals back into it, exactly like a synthetic input device:

- It **declares the signals it produces** (`declare_signals`); those join the
  input namespace so the config maps them like any real signal.
- It **runs functions bound in config**:
  - `[defaults] macro = m.fn()` - `fn()` runs every frame (always-on).
  - `[m.macro] BTN = fn()` - runs while `BTN` is held.
  - `[m.macro] BTN:press = fn()` / `BTN:release = fn()` - fires once on that edge
     (for latches and toggles, where "while held" can't see the release).
- It paces itself with `now_ms()` / `now()` (the run clock), reads the bus with
  `get_signal(name)`, learns which button triggered it via `trigger()`, and
  writes with `set_btn` / `set_axis`. Numeric call args (`fire(20)`) are optional.
  A missing trailing arg defaults, so one function is reusable across configs.

Because a macro is just a signal source, **a profile can have no input module at all**
The macro can be the source input, driven by a fixed-rate clock.
That is the self-test path example script listed below. 
For eg. You can program any macro or custom actions into a macro,
want to make a macro that plays all of super mario? go for it.

Two included macros show the range:

- `testpattern.qc` Sweeps the sticks, cycles the buttons, walks the hat. As a pure input source.
  `config/testpad_selftest.ini` drives the virtual test pad with no controller attached.
- `rapidfire.qc` A generic latch. A press-edge toggle arms it, then holding a face button pulses it instead of holding.
  An optional status LED (written as a generic `RF_LED` signal the config routes to any real LED on the real input device) shows the state of the macro.
  Stateful + timed + reads-and-writes the bus, exactly what a static config can't or should not be doing.
  See `config/ps5_to_xbox360.ini` for an example of this rapid fire macro in action, and examples of other advanced phidimus options.

---

## Modifier guards. Shift keys as config data

A shift key is **combinational inputs, not timed data**:
while a SHIFT key is held, this button means something else. No memory, no clock.
So it stays in the config as data **not** baked into an input module, **not** a macro:

```ini
BTN_SHIFT+BTN_LT  = XINPUT_GAMEPAD_LEFT_SHOULDER   ; only while SHIFT held
!BTN_SHIFT+BTN_LT = LEFT_TRIGGER                   ; only while SHIFT up / not in use
```

`MOD+FROM` gates a mapping on a modifier button being held; `!MOD+FROM` on it
being up. This is the line the engine draws everywhere:

> **Combinational conditions are config data. Anything with state or timing is a `.qc` module.**

The SideWinder profile (`config/SidewinderProPad_to_xbox360.ini`) uses guards to
route its two triggers to shoulder buttons or analog axes depending on
if BTN_SHIFT *and* the trigger buttons are pressed at the same time.
but does not do this alternative action when this shift key is not in use.
Allowing you to get near unlimited alternative inputs out of your input device.
this shift config lives in the ini so it's easily swappable and re-usable. 

---

## Handshake modules

Some devices send **nothing** until a console-style init wakes them:
"Hi, I'm the real console, start streaming data to me."
Examples: 
Switch Pro Controller (`handshakes/VID_057E&PID_2009.qc`)
PS3 controller (`handshakes/VID_054C&PID_0268.qc`)

These live in `handshakes/` separately from input modules **on purpose**:

- You can get a raw readout of a device (with `--hids` from the sdk) the moment the handshake
  works *before* writing any decode logic. No chicken and egg: You don't need
  a finished input module to test the wake-up, and you don't need the wake-up
  working to start sketching the input module decode.
- When your input module is ready, you can simply `import "handshakes/VID_xxxx&PID_xxxx.qc"`
  and call its `setup()` from `Open()` within your input module.
  The handshake code is written once and reused, never copy-pasted all over the place.
  For eg. use the same handshake code for switch pro controller and joycon as they are more or less the same.
  the VID and PID only need to match when using `--hids` otherwise you can just include whatever module you want.
- The handshake modules may include platform specific encryption keys that can be distributed or
  obtained from a real controller separately from the main input module.
  The handshake module could get dmca'ed for said encryption keys without it affecting the main input module.
- One user can make a handshake module and another user can make an input module based on that handshake
  and distribute them separately, then freely swap the handshake module to another if needed,
  without affecting the input module in any way.

A handshake module typically declares `KEEPALIVE_MS`/`OUTPUT_REPORT_LEN` and a
`setup()` (init sequence) plus optionally `keepalive()`
(devices like the Switch Pro Controller revert to low-res mode if not pinged every few seconds).

---

## Multi-device profiles

A config can bind multiple inputs and/or multiple outputs at once:

```ini
output = xbox360_windows, mouse_output
```

Real cases:
- DualSense -> Xbox 360 pad **and** mouse simultaneously
  `config/ps5_to_xbox360_and_mouse.ini`
  (touchpad drives the cursor while the sticks/buttons drive the game).
- A sim rig where a wheel and pedals are separate physical devices merged into
  one virtual controller.

Two design choices follow from this:
- **Outputs are an ordered list.** A minimal target (the Pi dongle for eg) can support just
  one output by reading the first entry and stopping graceful degradation of your config
  rather than a hard failure. only half of your config works now, not all of it.
- **Mappings are namespaced to their output** (`[xbox360_windows.buttons]`) so
  each output gets its own binding block. Helps minimize binding conflicts.

Multi-device is **supported but not a priority**, this means you can setup a config with just one input and output easily.
You don't have to setup a multi device config if you don't want to, and tbh it's not the default. Most of the time you only
want to or need to convert one device into another device. multi device is just another option phidimus engine supports.

---

## The binaries

| Binary | Role |
|---|---|
| `phidimus-sdk` | Full desktop test bench: `--mods`, `--probe`, `--hids`, `--usb`, `--calib`, live debug. Build and debug modules here. |
| `phidimus-shell` | Minimal runner: load config, convert, basic state logging only. The overhead model for embedded. |
| `phidimus-configurator` | GUI binding editor (separate concern; revisited after the 4.0 core). |
| `phidimus-pi` | Full Raspberry Pi build (Pi Zero 2 W / CM4) running the **whole Go stack natively** — quad-core arm64, real threads, no TinyGo, no cut-down engine. Drag-drop `.qc` + `.ini`, plug in, it's a dongle. Configure via an OLED HAT. |

Develop and verify on the SDK on pc, then drop the same modules + config onto dongle hardware. Or any device that runs phidimus engine.
The PC software is the SDK and test tool, the dongle is the product.
And because the output is a real USB device, that dongle controls exactly what the host target sees,
with no host driver in the loop. No steam input to overwrite on host, no need for hidhide to hide our input from host.
From the host device point of view you just plugged in a real controller via usb, no more, no less.