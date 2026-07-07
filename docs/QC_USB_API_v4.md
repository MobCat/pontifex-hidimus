# Phidimus Engine — QC module API (v4)

The reference for writing `.qc` modules. Shipped and current as of Engine 4.3.0:
every builtin and hook below is implemented and used by real modules in
`modules/`. For the *why* behind the layering, see
[architecture.md](architecture.md).

A `.qc` module is plain text (a small QuakeC-flavoured language), loaded at
runtime — drop it in `modules/` and it's live, no rebuild. There are two kinds:

- **Input modules** read a real controller (USB *or* Bluetooth) and turn its raw
  bytes into named signals. `DRIVER = "hid_input"` (HID-class) or
  `"winusb_input"` (vendor/raw, bound via Zadig — see [ZADIG.md](ZADIG.md)).
- **Output modules** *are* a virtual USB device the host binds its own driver to.
  `DRIVER = "usb_device"`.

(Macros are a third kind, `DRIVER = "macro"` — a clock-driven signal source
between input and output; documented in the main README.)

The design rule throughout: **capture reality, paste it.** Read what the real
device says with `--usb`, `--hids`, `--probe`, `lsusb`, or a pcap, then feed
those exact bytes back. Nothing here is guessed; it's captured.

---

## Every module: metadata

```qc
string MODULE_ID      = "ps5ds";     // unique id (the name in configs, --probe, --mods)
string MODULE_NAME    = "PlayStation 5 DualSense";
string MODULE_VERSION = "1.0.0";   // the module's own semver
string MODULE_AUTHOR  = "MobCat";
string ENGINE_VERSION = "4.3.0";   // the engine this module targets (warns if older)
string DRIVER         = "hid_input";
```

`DRIVER` selects the engine driver and therefore which lifecycle functions the
engine calls. The engine evaluates all globals at load in **source order**
(later re-declarations win — see *Variant modules* below), then calls the
lifecycle functions for that driver.

---

## Input modules (`hid_input` / `winusb_input`)

Read a physical controller over USB or Bluetooth. Lifecycle:
`declare_devices()` → `declare_signals()` → `setup()` (once, after open) →
`parse(raw)` (every report) → `write_feedback()` (when feedback changes).

### declare_devices() — which devices this module reads

```qc
void() declare_devices =
{
//  add_device(VID, PID, "Product name");
    add_device(0x054C, 0x05C4, "DualShock 4 v1 (CUH-ZCT1)");
    add_device(0x054C, 0x09CC, "DualShock 4 v2 (CUH-ZCT2)");
};
```

The engine tries each entry in order and opens the first one present — so one
module can cover a whole family of pads (and clones). A single-device module can
instead set `int VID = ...; int PID = ...;` globals and skip `declare_devices()`.

### declare_signals() — what the module produces (and consumes)

```qc
void() declare_signals =
{
    // Feedback buffer the module writes back to the device (LEDs/rumble).
    // feedback_len(n) sizes it; the engine grows it to BT_FEEDBACK_LEN on BT.
    feedback_len(32);
    feedback("RUMBLE_HEAVY", 0, 255);    // one named feedback channel + range
    feedback("LED_R", 0, 255);

    // Input signals this module reports:
    btn("BTN_CROSS");                    // a digital button
    axis("LEFT_STICK_X", -32768, 32767); // an analog axis + range

    // Optional: calibration fields exposed to --calib (feature-report editing).
    // calib_field("name", ...);  calib_field_ro(...) for read-only.
};
```

Signal *names* are the common language configs bind to — keep them
human-readable and consistent across modules (e.g. every stick is
`LEFT_STICK_X`) so a config maps by name with no device-specific logic.

### parse(raw) — decode one report

Called on every input report. Read bytes from `raw[i]`, write signals with
`set_btn(name, value)` / `set_axis(name, value)`.

```qc
void(bytes raw) parse =
{
    local int o = IS_BT;                  // BT reports are offset +1 vs USB here
    set_axis("LEFT_STICK_X", raw[1 + o]);
    set_btn("BTN_CROSS", raw[8 + o] & 0x20);
};
```

See `modules/input/ps5ds.qc` for a full, capture-confirmed example (sticks, IMU,
touchpad, battery, USB + BT in one module).

### Bluetooth vs USB — the transport globals

One module handles both links; the engine sets `IS_BT` after `Open()` and the
module branches on it. The relevant globals:

| Global | Set by | Meaning |
|---|---|---|
| `IS_BT` | **engine** (module reads) | 1 when the open link is Bluetooth, 0 for USB. Gate BT-only code on this. |
| `TRANSPORT` | module | `"usb"` or `"bt"` hint to bias which link the driver prefers. Omit to auto-detect (USB preferred). |
| `STALL_TIMEOUT_MS` | module | if the pad streams continuously, going silent this long = link dropped → the engine reconnects and re-selects the best transport. |
| `BT_FEEDBACK_LEN` | module | the feedback buffer grows to this on BT (e.g. 78 for the DualSense 0x11 report) so `write_feedback()` has room for the BT layout + CRC. |
| `OUTPUT_REPORT_LEN` / `OUTPUT_REPORT_LEN_BT` | module | zero-pad each output write to this many bytes (Windows BT HID wants the full report length, e.g. 547). |
| `USE_SET_OUTPUT_REPORT` | module | send feedback via `HidD_SetOutputReport` instead of `WriteFile` (some stacks require it). |
| `KEEPALIVE_MS` | module | re-send the last output report on this interval to keep a link alive. |

### setup() — one-time init after the device opens

Runs once after `Open()`, with `IS_BT` already set. USB pads usually stream the
full report immediately (no-op here); Bluetooth pads often need waking. The
classic DualShock/DualSense case: **reading a calibration feature report flips
the pad into its full report mode.**

```qc
void() setup =
{
    if (!IS_BT) { return; }
    read_feature(0x02, 37);    // reading calibration flips DS4 into full 0x11 mode
    read_feature(0x05, 41);
    // then optionally send a first output report to set the lightbar / confirm host:
    set_feedback_byte(0, 0x11);
    // ... header + RGB ...
    feedback_crc32_sony_bt();   // Sony's BT reports end in a CRC32
    send_feedback_buf();
};
```

### write_feedback() — LEDs / rumble back to the pad

Build the device's output report in the feedback buffer with
`set_feedback_byte(i, v)` (read a routed value with `get_feedback(name)`), add a
CRC if the wire format needs one, and `send_feedback_buf()`. The config routes
signals into the named feedback channels via a `[<module>.feedback]` section.

### Feature passthrough

`read_feature(id, len)` reads a HID feature report from the physical device. This
also powers **passthrough**: a virtual output device's `on_get_feature(id)` can
return the *real* controller's feature bytes (calibration, pairing/MAC), so a
game that interrogates the pad before trusting it gets authentic answers.

---

## Output modules (`usb_device`)

Present a virtual USB device. The OS binds its own driver (xusb22.sys for a 360
pad, the HID stack for a DualSense, the console's own vendor code for an XID
pad). Lifecycle: `declare_usb()` → `declare_signals()` → `pack()` (per host IN
poll) → `on_output(raw)` (host→device reports) → optional control-transfer hooks.

### Identity globals

Own the device descriptor — brand it, or paste the real hardware's exact
identity so a picky driver/anti-cheat has nothing to flag.

| Global | Meaning |
|---|---|
| `USB_VID` / `USB_PID` | vendor / product id |
| `USB_BCD_DEVICE` | device release (bcdDevice), e.g. `0x0121` |
| `USB_BCD_USB` | USB spec version (bcdUSB); **defaults to `0x0200`** (2.00), set `0x0100` to report USB 1.00 like a real wired Xbox 360 pad |
| `USB_EP0_SIZE` | control-endpoint max packet (8 / 64) |
| `USB_CLASS` / `USB_SUBCLASS` / `USB_PROTOCOL` | device descriptor class triple (omit for per-interface `00/00/00`) |
| `USB_MANUFACTURER` / `USB_PRODUCT` / `USB_SERIAL` | string descriptors (empty = "no string", see below) |
| `USB_SPEED` | wire speed (default full-speed) |

### declare_usb() — the device layer

Paste the configuration descriptor verbatim (the engine parses interfaces,
endpoints, and intervals out of it) and name the endpoints. Adjacent string
literals concatenate, so a descriptor can be one commented line per structure:

```qc
void() declare_usb =
{
    usb_config(
        "09 02 20 00 01 01 00 80 32"   // configuration
        "09 04 00 00 02 58 42 00 00"   // interface 0: class 58/42/00 (XID)
        "07 05 81 03 20 00 04"         // EP 0x81 IN,  interrupt, 4 ms
        "07 05 02 03 20 00 04"         // EP 0x02 OUT, interrupt, 4 ms
    );
    in_endpoint(0x81);    // pack() reports go out here
    out_endpoint(0x02);   // host reports (rumble) arrive here -> on_output()
};
```

- `usb_config(hex)` — the configuration blob (device layer; the `--usb` view).
- `usb_hid_report_descriptor(hex)` — HID-class devices only (returned for
  GET_DESCRIPTOR type 0x22). Omit for vendor-class (XID, XUSB).
- `usb_device_descriptor(hex)` — **optional** verbatim 18-byte device descriptor,
  the full "capture reality, paste it" escape hatch for bytes the `USB_*` globals
  can't express, or a computed one: `usb_device_descriptor(build_desc(serial))`.
  When present it wins over the synthesised descriptor and the engine reads
  VID/PID/bcdDevice/class back off it (keeping the `--usb`/devlist view in sync);
  a short (`<18` byte) blob is ignored and the globals are used instead. When
  absent, the descriptor is synthesised from the globals as usual — so a baseline
  device still enumerates without spelling out every byte, and you tweak only what
  you need (e.g. just `USB_BCD_USB`).
- `usb_string(index, "text")` — extra string descriptors beyond the `USB_*` ones.
  The index is any descriptor index (hex is fine and reads best against the
  descriptor bytes that reference it, e.g. `usb_string(0x04, "Xbox Security
  Method 3, Version 1.00, © 2005 Microsoft Corporation. All rights reserved.")`).
- `in_endpoint(addr)` / `out_endpoint(addr)` — wire `pack()` and `on_output()` to
  the right endpoints (addresses as they appear in the descriptor, e.g. `0x81`).

### declare_signals() — the signal layer

```qc
void() declare_signals =
{
    report_len(20);                             // input report size
    out_btn("XINPUT_GAMEPAD_A", 0x1000);        // name -> bitmask in the report
    out_axis("LEFT_STICK_X", -32768, 32767);    // name + range
    out_feedback("RUMBLE_LARGE", 0, 255);       // a host->device feedback channel
    // out_feedback_blob("NAME");               // a variable-length feedback blob
};
```

### pack() — build the input report

Called to produce the report the host reads on its IN poll. Read the mapped
output state with `get_buttons()` (the OR of active `out_btn` masks) and
`get_axis(name)`; write with `set_report_byte(i, v)` / `set_report_word(i, v)`
(16-bit little-endian).

```qc
void() pack =
{
    set_report_byte(0, 0x00);
    set_report_byte(2, get_buttons() & 0xFF);
    set_report_word(12, get_axis("LEFT_STICK_X"));  // signed, two's-complement LE
};
```

Axis **direction is a config concern** (`invert=`), never hidden in `pack()` —
write signals verbatim so the config owns polarity.

### on_output(raw) — host → device reports

The host sends rumble/LED/adaptive-trigger reports to the OUT endpoint. Decode
them and publish with `set_out_feedback(name, v)`; the mapper routes those to the
input device's feedback. Use `set_out_feedback_blob(name, bytes)` /
`blit_feedback_blob(name, offset, bytes)` for variable-length data (e.g. adaptive
triggers).

```qc
void(bytes raw) on_output =
{
    if (raw[0] == 0x00) {                 // rumble report id
        set_out_feedback("RUMBLE_LARGE", raw[3]);
        set_out_feedback("RUMBLE_SMALL", raw[4]);
    }
};
```

The engine resets these to 0 when the host link drops, so a mid-session
disconnect doesn't leave the pad stuck (e.g. rumble buzzing).

### Control-transfer hooks — `return hex(...)`

For requests the engine doesn't answer from the descriptors, three optional
hooks let the module reply. **They reply by returning bytes** — build them with
`hex("...")`; returning nothing STALLs the request.

```qc
// Vendor / unusual control requests (the catch-all). Original-Xbox XID pads use
// this: the console fetches the XID descriptor with a vendor request, not from
// the config descriptor.
bytes(int bmReqType, int bReq, int wValue, int wIndex, int wLength) on_control =
{
    if (bReq == 0x06 && wValue == 0x4200) {         // GET_DESCRIPTOR(XID)
        return hex("10 42 00 01 01 02 14 06 FF FF FF FF FF FF FF FF");
    }
    return hex("");                                  // unrecognised -> empty
};
```

**Reading the OUT data stage (host→device payloads).** A control request can carry
a data payload *from* the host — e.g. a console writing an authentication challenge.
Declare **one extra `bytes` parameter** and `on_control` receives that payload; the
5-argument form above never sees it and keeps working unchanged (the parameter is
opt-in by arity). This is how a challenge/response handshake (e.g. the Xbox 360's
XSM3) reads what the console sent before computing its reply:

```qc
bytes(int bmReqType, int bReq, int wValue, int wIndex, int wLength, bytes out) on_control =
{
    if (bReq == 0x82) {              // console SET: a challenge write, `out` = its bytes
        stash_challenge(out);        // keep it; a later IN request (bReq 0x83) returns the reply
        return hex("");              // OUT transfers have no data to return
    }
    return hex("");
};

// HID feature reports (GET/SET). on_get_feature returns the bytes; the engine
// falls back to reading the physical device if the hook returns nothing.
bytes(int report_id) on_get_feature =
{
    if (report_id == 0x05) { return hex("05 1E FF FC ..."); }  // captured blob
    return hex("");
};
void(int report_id, bytes raw) on_set_feature = { /* accept + ignore is valid */ };
```

The engine auto-answers `GET_REPORT(input)` with the last `pack()`ed report, and
delivers host OUT reports that arrive on EP0 (`SET_REPORT`) to `on_output()` too
— so a module rarely needs `on_control` unless it's a vendor device like the XID.

See `modules/output/xboxog_rawusb.qc` (vendor XID) and
`modules/output/xbox360_usb.qc` (XUSB) for complete real examples.

---

## Feedback shaping — `scale`, `curve`, `map` (config side)

A module publishes feedback signals by name (`out_feedback(...)` on the output side,
`feedback(...)` on the input side); the **config** shapes the value between signals.
This is engine-general — no device knowledge here — and applies to both
`[<output>.feedback]` (e.g. console rumble → pad actuators) and `[<input>.feedback]`
(e.g. battery level → lightbar) sections.

Three knobs, all 0–255 in / 0–255 out:

- **`scale=`** — a linear multiplier applied first (`scale=0.5` halves it).
- **`curve=`** — an intensity shape. On its own it shapes the whole 0–255 range;
  **with a `map=` it shapes the fill *between* the stops**.
- **`map=[in:out, ...]`** — a table of **anchor** points, clamped outside the range.

### The curves

Every curve maps a normalised position `t` (0→1) to an output (0→1), pinning the ends:

| `curve=` | shape | `t=0.25` | `t=0.5` | `t=0.75` | feel |
|----------|-------|:--:|:--:|:--:|------|
| `linear` (default) | `t` | 0.25 | 0.50 | 0.75 | straight line, faithful |
| `natural` | `t^0.75` | 0.35 | 0.59 | 0.81 | gentle lift of low/mid — good "voice-coil" rumble feel |
| `sqrt` | `√t` | 0.50 | 0.71 | 0.87 | strong lift of low values (fast rise, then flattens) |
| `square` | `t²` | 0.06 | 0.25 | 0.56 | suppresses low values (slow rise, then steepens) |

(As 0–255: `natural` turns a half-strength `128` into ≈`152`; `sqrt` into ≈`180`;
`square` into ≈`64`.)

### map + curve compose

The stops are **anchor points you pin**; `curve=` fills the gaps between them
(default linear). A map needs at least a start and an end; add as many in-between
stops as you like to hand-place the shape, and the curve catches the values you
didn't pin.

```ini
# Linear fill (no curve): halfway between the 40 and 90 stops → halfway 0..255 = 128.
TRIGGER_STRENGTH = WHEELFEEDBACK, map=[0:0, 40:0, 90:255]

# Same anchors, but the fill between them follows the natural curve instead of a line.
TRIGGER_STRENGTH = WHEELFEEDBACK, map=[0:0, 40:0, 90:255], curve=natural
```

Order of operations: **do the map (anchors), then the curve fills the blanks.** Omit
`map=` and `curve=` alone shapes the whole range; omit `curve=` and the map is a plain
straight-line/exact table (that's why discrete lookups like an LED-ring pattern →
player dots must NOT set a curve — they rely on exact linear stops).

Unknown curve names are rejected at load (they don't silently fall back to linear).
A namespaced curve like `curve=ps5ds.FFB` — a module/macro-provided custom curve,
including scalar→blob expanders — is a **planned** feature and currently errors.

---

## Transports — where the virtual device appears

The output module is transport-agnostic; the config's `method =` picks how it's
presented:

- **`usb_ip`** (desktop default) — served over USB/IP; the OS binds its driver
  via a signed USB/IP client. Auto-attaches on `127.0.0.1:3240` (override with
  the `usbip` config key).
- **`usb_gadget`** (phidimus-pi, FunctionFS) — a real USB device on the Pi's
  own port. Works for standard HID/vendor devices.
- **`raw_gadget`** (phidimus-pi) — also a real USB device, but hands every
  descriptor and setup packet to userspace **verbatim**. Required when the
  descriptor carries a vendor block FunctionFS would reject (the Xbox 360's
  17-byte `0x21` descriptor, the original Xbox XID) — i.e. real-console output.
  Off-hardware it falls back to USB/IP.

The same `declare_usb()` drives all three.

---

## Variant modules: import a base and override

A near-identical device (same protocol, a few different descriptor bytes) does
NOT need a whole new module. `import "base.qc"` at the **top** pastes the base
module's text; anything declared **below** it wins — globals *and* functions are
both **last-in-the-text-wins**. A variant overrides only what differs and
inherits `declare_signals` / `pack` / `on_output` unchanged:

```qc
import "xboxog_rawusb.qc"          // the Controller S: all the real work

string MODULE_ID = "xboxog_duke";  // override identity + the few descriptor bytes
int    USB_PID   = 0x0202;
void() declare_usb = { /* Duke's endpoint 0x82 */ };
bytes(int,int,int,int,int) on_control = { /* Duke's XID subtype */ };
```

`import` is a textual paste at that line, resolved before parsing, so ordering is
positional: import first, overrides after. This is the same `import` used to pull
in `handshakes/…` files. See `modules/output/xboxog_duke.qc`.

---

## String descriptors: empty string = "no string" (index 0)

An empty `USB_MANUFACTURER` / `USB_PRODUCT` / `USB_SERIAL` makes the engine set
that descriptor **index byte to 0** — "this device has no such string," so the
host never requests it. This matches hardware that shows `---` in UsbTreeView
(`iManufacturer = 0`), and avoids a non-zero index pointing at a missing string,
which can make Windows STALL during enumeration. So `USB_MANUFACTURER = ""` is
the "not set" signal, not a placeholder. (QC has no `null`; the empty string is
the idiom. See `buildUSBConfig` in internal/qcvm/usbmodule.go.)

Edge case: this cannot express a *referenced zero-length* string (an
`iManufacturer = 1` pointing at a header-only, character-less descriptor). Nothing
we emulate needs it; it would take a small engine change if some device ever did.

---

## Builtin reference

Grouped by where they're used. Everything here is registered in
`internal/qcvm/builtins.go`.

**Any function**
| Builtin | Purpose |
|---|---|
| `hex("AA BB ..")` | parse a whitespace-separated hex string to bytes (control/feature replies) |
| `print(...)` | debug line to stderr |
| `now_ms()` / `now()` | ms / seconds since the run started |

**Input — declare_devices**
| Builtin | Purpose |
|---|---|
| `add_device(vid, pid, "name")` | register a device this module can read |

**Input — declare_signals**
| Builtin | Purpose |
|---|---|
| `btn("NAME")` / `axis("NAME", min, max)` | declare an input signal |
| `feedback("NAME", min, max)` / `feedback_len(n)` | declare a feedback channel / size the buffer |
| `calib_field(...)` / `calib_field_ro(...)` | expose a `--calib` field (feature-report editing) |

**Input — parse / setup / write_feedback**
| Builtin | Purpose |
|---|---|
| `set_btn("NAME", v)` / `set_axis("NAME", v)` | publish a decoded signal |
| `get_feedback("NAME")` | read a routed feedback value |
| `set_feedback_byte(i, v)` / `send_feedback_buf()` | build + send the device output report |
| `feedback_crc32_sony_bt()` | append Sony's BT report CRC32 |
| `read_feature(id, len)` / `write_feature(...)` / `write_feature_buf()` | HID feature report I/O (activation, passthrough) |
| `write_output(...)` / `read_next()` / `sleep_ms(n)` / `next_counter()` | raw output write / blocking read / delay / rolling counter |

**Output — declare_usb**
| Builtin | Purpose |
|---|---|
| `usb_config(hex)` | configuration descriptor blob |
| `usb_device_descriptor(hex)` | verbatim 18-byte device descriptor (optional; else synthesised from `USB_*`) |
| `usb_hid_report_descriptor(hex)` | HID report descriptor (HID class only) |
| `usb_string(index, "text")` | extra string descriptor |
| `in_endpoint(addr)` / `out_endpoint(addr)` | wire pack() / on_output() to endpoints |

**Output — declare_signals**
| Builtin | Purpose |
|---|---|
| `report_len(n)` | input report size |
| `out_btn("NAME", mask)` / `out_axis("NAME", min, max)` | output button (bitmask) / axis |
| `out_feedback("NAME", min, max)` / `out_feedback_blob("NAME")` | host→device feedback channel / blob |

**Output — pack**
| Builtin | Purpose |
|---|---|
| `get_buttons()` / `get_axis("NAME")` | read the mapped output state |
| `set_report_byte(i, v)` / `set_report_word(i, v)` | write the report (byte / 16-bit LE) |

**Output — on_output**
| Builtin | Purpose |
|---|---|
| `set_out_feedback("NAME", v)` | publish decoded host feedback (rumble/LED) |
| `set_out_feedback_blob("NAME", bytes)` / `blit_feedback_blob("NAME", off, bytes)` | variable-length feedback (adaptive triggers) |

**Macros** (`DRIVER = "macro"`)
| Builtin | Purpose |
|---|---|
| `get_signal("NAME")` | read the merged signal bus (buttons return 0/1) |
| `trigger()` | the button that fired this call (for `fire()`-style macros) |
| `set_btn` / `set_axis` | write signals back to the bus |

---

## What the engine does for you (never written in QC)

- Builds the device descriptor from the `USB_*` globals.
- Answers all USB chapter-9 boilerplate: GET_DESCRIPTOR (device / config /
  string / HID report), SET_CONFIGURATION, SET_IDLE, GET_STATUS,
  GET_REPORT(input) (served from the last `pack()`), and routes EP0 SET_REPORT
  OUT data to `on_output()`.
- Queues endpoint URBs: host IN polls get the latest `pack()`ed report at the
  descriptor's interval.
- USB/IP framing, attach/detach, and reconnect; endpoint release + feedback
  reset on a mid-session host disconnect (raw-gadget).
- On the input side: opens USB or Bluetooth, sets `IS_BT`, grows the feedback
  buffer for BT, throttles feedback writes, and reconnects on stall.
- On phidimus-pi: the same module drives the board's real USB port instead of
  USB/IP, via FunctionFS or raw-gadget.
