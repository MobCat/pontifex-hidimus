# The original Xbox controller (XID) — enumeration, descriptors & reports

Everything the original Xbox's controller looks like on the wire, and every request
the console makes of it during bring-up. All bytes here are **captured from real
hardware** — a real Controller S (`045E:0289`) and a real Duke (`045E:0202`) read with
`phidimus-sdk --usb`, and the live console enumeration captured on a real Xbox with
`log_host_port`
"Capture reality, paste it."

This is the reference behind [modules/output/xboxog_rawusb.qc](../modules/output/xboxog_rawusb.qc)
(Controller S) and [modules/output/xboxog_duke.qc](../modules/output/xboxog_duke.qc)
(the Duke variant), and the top rung of the [output test ladder](output-test-ladder.md).

---

## What it is

The Xbox controller is an **XID** device — a **vendor** class (`0x58 / 0x42 / 0x00`),
**not** HID. It is USB 1.1, full-speed, bus-powered. Two interrupt endpoints: an IN for
the 20-byte input report and an OUT for the 6-byte rumble report. Unlike the Xbox 360
(whose vendor `0x21` descriptor rides *inside* the configuration descriptor), the XID
descriptor and the capability reports are fetched over **EP0 vendor control requests**.

The console does **no controller authentication** (unlike the 360's XSM3), so a faithful
bare XID device is accepted directly — no hub required (the ogx360 precedent). A real pad
is physically a 3-port hub with the controller on port 1 and memory-card/expansion slots
on 2–3, but the console talks to the controller function directly; we present just that
function.

### Two variants

Same XID device; **five bytes differ**:

| Field | Controller S `045E:0289` | Duke `045E:0202` |
|-------|--------------------------|------------------|
| idProduct | `0x0289` | `0x0202` |
| bcdDevice | `0x0121` | `0x0100` |
| bMaxPacketSize0 (EP0) | `0x08` (8) | `0x40` (64) |
| IN endpoint address | `0x81` | `0x82` |
| XID `bSubType` | `0x02` (gamepad S) | `0x01` (gamepad / Duke) |

Everything else, the config layout, the 20-byte input report, the 6-byte rumble, and
the capability reports are identical.
Some OG-Xbox games read the PID / XID subtype to tell which pad is plugged in, 
which is why the Duke variant exists.
Config layout (GET_CAPABILITIES) may be difrent for more speclised contolers, like the racing wheel or steal betalioin
contoler but this is untesed, and to hased a guess probs just uses the VID and XID as an idintifyer.

---

## Descriptors

### Device descriptor (Controller S) — 18 bytes

```
12 01 10 01 00 00 00 08 5E 04 89 02 21 01 00 00 00 01
```

| Bytes | Field | Value |
|-------|-------|-------|
| `12` | bLength | 18 |
| `01` | bDescriptorType | DEVICE |
| `10 01` | bcdUSB | 1.10 |
| `00 00 00` | bDeviceClass/Sub/Proto | 0/0/0 (per-interface) |
| `08` | bMaxPacketSize0 | 8 (Duke: `40` = 64) |
| `5E 04` | idVendor | `0x045E` Microsoft |
| `89 02` | idProduct | `0x0289` (Duke: `0202`) |
| `21 01` | bcdDevice | `0x0121` (Duke: `0100`) |
| `00 00 00` | iMfr/iProd/iSerial | none — **no string descriptors** |
| `01` | bNumConfigurations | 1 |

### Configuration descriptor — 32 bytes total (`wTotalLength = 0x20`)

```
09 02 20 00 01 01 00 80 32   configuration: 1 interface, bus-powered, 100 mA
09 04 00 00 02 58 42 00 00   interface 0: class 58/42/00 (XID), 2 endpoints
07 05 81 03 20 00 04         EP 0x81 IN,  interrupt, 32 B, 4 ms   (Duke: 0x82)
07 05 02 03 20 00 04         EP 0x02 OUT, interrupt, 32 B, 4 ms
```

### XID descriptor — 16 bytes (fetched via `C1 06 4200`)

```
10 42 00 01 01 02 14 06 FF FF FF FF FF FF FF FF
```

| Bytes | Field | Value |
|-------|-------|-------|
| `10` | bLength | 16 |
| `42` | bDescriptorType | XID (`0x42`) |
| `00 01` | bcdXid | 1.00 |
| `01` | bType | 1 (game controller) |
| `02` | bSubType | gamepad S (Duke: `01`) |
| `14` | bMaxInputReportSize | 20 |
| `06` | bMaxOutputReportSize | 6 |
| `FF × 8` | wAlternateProductIds[4] | none (`0xFFFF × 4`) |

---

## Enumeration (captured on a real Xbox)

The console drives exactly **seven** EP0 control transfers, in this order, then starts
polling the interrupt endpoints. `wIndex` is `0x0000` throughout.

| # | bmReqType | bReq | wValue | wLen | Meaning |
|---|-----------|------|--------|------|---------|
| 1 | `0x80` | `0x06` | `0x0100` | 8 | GET_DESCRIPTOR(device) — **first 8 bytes only** (reads bMaxPacketSize0) |
| 2 | `0x80` | `0x06` | `0x0200` | 80 | GET_DESCRIPTOR(config) — asks 80, gets the 32 real bytes |
| 3 | `0x00` | `0x09` | `0x0001` | 0 | SET_CONFIGURATION(1) |
| 4 | `0xc1` | `0x06` | `0x4200` | 16 | GET XID descriptor (vendor/IN/interface) |
| 5 | `0xa1` | `0x01` | `0x0100` | 20 | HID-style GET_REPORT(input) — initial state read |
| 6 | `0xc1` | `0x01` | `0x0200` | 6 | GET_CAPABILITIES(output/rumble) |
| 7 | `0xc1` | `0x01` | `0x0100` | 20 | GET_CAPABILITIES(input) |

`bmRequestType` decode: `0x80` = IN/standard/device, `0x00` = OUT/standard/device,
`0xa1` = IN/class/interface, `0xc1` = IN/**vendor**/interface. The three `0xc1` requests
are the XID-specific ones answered in the module's `on_control()`; requests 1–3 and 5 are
served by the engine's descriptor/GET_REPORT machinery.

**It's a minimal enumeration** — the console reads only 8 bytes of the device descriptor,
never the full 18, and reads **no string descriptors** at all. It trusts the config +
XID. (Contrast Windows, which reads everything including strings.)

### Capability reports

Each is a mask laid over its report: `0xFF` = field present, `0x00` = an unused/reserved
byte.

- **Input** (`C1 01 0100`, 20 B): `00 14 FF 00 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF`
  — byte 0 type, byte 1 length (20), byte 2 the digital-button byte, byte 3 the reserved
  gap (`00`), bytes 4–19 all present (analog buttons, triggers, sticks).
- **Output** (`C1 01 0200`, 6 B): `00 06 FF FF FF FF` — both 16-bit motor fields present.

---

## Reports

### Input report — 20 bytes (device → console, EP 0x81 / Duke 0x82)

Note the face buttons are **analog** (0–255 pressure), not bits.

| Byte(s) | Field |
|---------|-------|
| 0 | report type `0x00` |
| 1 | report length `0x14` (20) |
| 2 | digital buttons bitmask: `01` DPAD-Up · `02` Down · `04` Left · `08` Right · `10` Start · `20` Back · `40` L3 · `80` R3 |
| 3 | reserved (`0x00`) |
| 4–9 | analog face buttons A, B, X, Y, Black, White (0–255 each) |
| 10–11 | analog triggers: Left, Right (0–255) |
| 12–19 | sticks LX, LY, RX, RY — `int16` little-endian (`-32768:32767`) each |

`pack()` writes this verbatim; stick direction is a config concern (`invert=`), never
hidden in the module (an earlier hidden `-Y` negate fought a config `invert=true` and
showed Y upside-down on a real console — fixed).

### Rumble report — 6 bytes (console → device, EP 0x02)

```
[0] 0x00 type   [1] 0x06 length
[2..3] left  (heavy) actuator, 16-bit LE — level in the high byte [3]
[4..5] right (light) actuator, 16-bit LE — level in the high byte [5]
```

Captured live from the console's controller-test rumble sweep (log 037): the console
duplicates the 8-bit level into both bytes of each 16-bit field, e.g. right motor ramping
`00 06 00 00 d7 d7` → `… ff ff` → `… 00 00`, then the left motor `00 06 e1 e1 00 00` →
`… ff ff 00 00`. `on_output()` reads `raw[3]` (left level) and `raw[5]` (right level) as
0–255 and routes them back to the physical input device via `[<module>.feedback]`.

---

## Force feedback over EP0 — the racing-wheel edge case (unfinished, not a limitation)

Most games send rumble the normal way — the 6-byte report on the **interrupt-OUT
endpoint (EP 0x02)** above. That path is rock-solid: it has soaked for 17+ minutes of
continuous rumble on hardware (log 055) and never faltered.

**One game so far behaves differently.** Colin McRae Rally 2005 sends **zero** interrupt-OUT
reports and instead drives force feedback as a **HID `SET_REPORT` on EP0**
(`bmReqType=0x21 bReq=0x09 wValue=0x0200`, 6 bytes), a steady **~25 reports/second**. The
payload is `00 06 V V V V` — a **single mono force value** replicated across all four data
bytes (not the L/R stereo of interrupt-OUT rumble), i.e. an FFB *magnitude*, in-game only,
tracking the force on the car (logs 043/061).

### Why: we're being both a gamepad and a wheel at once

The working theory (consistent with every capture, not yet confirmed against real
hardware): Colin McRae supports a **force-feedback racing wheel** (the Fanatec Speedster 3
ForceShock is the period wheel for it). That wheel is presumably a **HID** device — or has
firmware/hardware built to service this EP0 `SET_REPORT` output stream correctly. An XID
**gamepad** is *not* HID and normally never sees this request.

Our `xboxog_rawusb` device is **promiscuous** — it accepts whatever the host sends,
including this HID output report. So the game treats us as wheel-capable and streams FFB
over EP0, while we're also presenting as a plain gamepad. We're trying to be **both devices
at once**, which is what confuses the game's output routing. A real controller would be one
or the other.

### The wedge: a dwc2 race condition, below our code

Sustained EP0-OUT control writes eventually trip a **race condition in the Pi's dwc2 USB
device controller**:

```
dwc2 3f980000.usb: dwc2_hsotg_ep_stop_xfr: timeout DOEPCTL.EPDisable
```

dwc2 fails to disable/stop the EP0-OUT endpoint, so every subsequent `EP0_READ` returns
`EBUSY` and the transfer never completes → the console blocks on the unanswered control
transfer → the game freezes with the last force value stuck on the pad. Key facts:

- **It's below us, in the controller driver** — not our logging (proven: logs 048 with
  logging on vs 051 with it off both wedged, 051 *sooner*), and not us being too slow (the
  stream is a flat 25/s = 40 ms apart, huge slack, yet it wedges anyway).
- **It's a race, not a threshold** — the same steady load wedges at wildly different times,
  6 s to 150 s apart (log 061). Nothing we send *deterministically* triggers it.
- **Only a full gadget re-bind clears it** — a manual profile restart, or the auto-recovery
  below. Retrying or stalling the wedged endpoint does not.

### Behaviour choice: keep the rumble

We deliberately **accept** the EP0 `SET_REPORT` (so the DualSense rumbles in-game) rather
than **stall** it. Stalling was tried on hardware: the game responds by sending **no force
reports at all** — no rumble whatsoever (possibly a safety behaviour: don't drive a wheel
that just rejected a command). The call is that **working rumble with a rare, recoverable
freeze beats no rumble**. See [[feedback-logging-never-blocks-device]] for the related rule
that the report handling must never block the driver path.

### Auto-recovery (mitigation, shipped)

Rather than freeze until a manual restart, `recoverWedge` in
[rawgadget_linux.go](../internal/usbgadget/rawgadget_linux.go) detects the **confirmed**
wedge (persistent `EBUSY` on the EP0 OUT read — a few 1 ms re-reads distinguish the real
wedge from a one-off transient, so it never tears down speculatively) and **re-enumerates
the gadget in place**: drain pumps → zero the stuck rumble → close the fd (resets dwc2) →
hold down a short settle → re-bind. The console sees a clean disconnect/reconnect and
re-grabs the controller; the DualSense's Bluetooth link is untouched, so it stays paired.
Fully logged, including the true controller-gone time:

```
usbgadget: OG Xbox EP0-FFB dwc2 wedge — auto-recovering (teardown + re-enumerate)
usbgadget: auto-recover: gadget re-bound in 15ms — waiting for the host to re-enumerate the controller
usbgadget: auto-recover COMPLETE — controller re-enumerated 144ms after the wedge (mid-race dropout)
```

On hardware (log 061) this recovers as a **sub-second on-screen "reconnect controller"
flash → back to the pause menu**. Open observations still being characterised (small sample
size — needs more runs):

- **Too-fast a re-bind can re-wedge quickly.** A 15 ms re-bind is below USB port debounce;
  once it recovered and re-wedged 6 s later. A `wedgeReenumSettle` gap (holding the device
  down ~100 ms so the console cleanly registers the disconnect and dwc2 fully clears) is the
  current lever, being tuned on hardware.
- **A hard console lock was seen once**, after several rapid recovery cycles in one session
  (including a first-ever lock while sitting in a *menu*). **Not yet attributable** —
  sample size 1; it may be the underlying dwc2/console issue rather than the recovery. More
  runs needed before drawing a conclusion.

### The proper fix (future — needs hardware we don't have yet)

The end state is **two accurate devices instead of one that pretends to be both**:

- a faithful plain-gamepad `xboxog_rawusb` that a game drives over the robust interrupt-OUT
  path (like every other game), and
- a separate **`xboxog_racingwheel.qc`** that presents as the wheel and services the EP0 FFB
  stream the way real wheel hardware does.

Getting there needs two things we don't have: a **real OG Xbox force-feedback wheel** to
capture how it answers this EP0 stream, and a **Pi build with USB-in *and* USB-out** so we
can MITM-log the full host↔device pump end-to-end (the current Zero 2 W has a single USB
data port, committed to output). Until then, auto-recovery is the mitigation and this is a
tracked, in-progress edge case — see the roadmap.

---

## Port / player: the console tells the device nothing

Hardware-confirmed (logs 032/033/034/036/037, `log_host_port`, across console ports 1, 2,
and 4): **every port enumerates byte-for-byte identically**, `wIndex = 0x0000` in every
request, and there is no port/player field anywhere — not in enumeration, not in the XID
capabilities, and the rumble report has no player field. The console assigns the player by
its own physical hub-port topology, invisible to the device.

**Consequence:** there is no way for the controller to learn which port/player it is on an
OG Xbox, so a device-side player indicator (e.g. a DualSense player-LED matching the port)
is impossible — it would have to be hardcoded in the profile. (The Xbox 360 differs: it
sends the player number as an **OUT report**, the LED-ring command — a `log_transport_frames`
event, not enumeration.)

---

## How phidimus answers it

- **Descriptors + GET_REPORT** (requests 1–3, 5): the engine's `usb_device` machinery,
  from `declare_usb()` (device + config) and the packed input report.
- **The three `0xc1` vendor requests** (4, 6, 7): the module's `on_control()`, returning
  the pasted XID descriptor and capability bytes.
- **Rumble** (EP 0x02): `on_output()` decodes the 6-byte report to `RUMBLE_LEFT` /
  `RUMBLE_RIGHT` feedback signals.
- **The Duke** imports the Controller S module and overrides only the five differing bytes
  (`import "xboxog_rawusb.qc"` + last-in-the-text-wins globals).

