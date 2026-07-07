# Roadblock: DualSense rich (audio) haptics over Bluetooth

## UPDATE (2026-06): protocol already cracked openly — see SAxense / DS5Dongle

The premise below ("need a PS5 / break BT crypto") is **superseded**. The
DualSense BT haptic protocol has been reverse-engineered in the open, clean-room:

- **egormanga/SAxense** — C proof-of-concept that sends real HD haptic PCM audio
  to a DualSense over Bluetooth with NO PS5, using retail gear + public clues
  (chiaki-ng, controller wikis). Haptic audio format: **unsigned 8-bit PCM,
  3000 Hz, 2 channels** (the two actuators). Linux/PipeWire-based.
- **awalol/DS5Dongle** — productizes it on the **RP2350 (Pi Pico 2 W)** — our
  phidimus-pi target — as a BT-host dongle: DualSense in over BT, USB DualSense
  (with HD haptics + speaker + mic) out to the PC. Credits SAxense.

So this is **real haptics, not a down-sample to basic rumble** (DSX-over-USB
style). Key enabler: you must **be the Bluetooth host** (own the BT stack) to
speak the protocol — SAxense controls Linux's stack, DS5Dongle owns the Pico's.
This fits phidimus-pi (BT-host dongle) far better than the desktop Windows path
(at the mercy of the OS BT stack). The original analysis below is kept for
context; Option 4 (reverse-engineer) is effectively DONE by SAxense.

---

Status (original): **blocked / likely infeasible to replicate faithfully.** Adaptive
triggers, basic rumble, LEDs, touch, and gyro all work through the BT→virtual-USB
passthrough (see `modules/output/ps5_usb.qc`). The one thing that doesn't is the
*rich* haptics — the fine-grained rumble (rain, footsteps, weapon texture) games
like Returnal lean on heavily.

## Why — the device is two things in one connection

The DualSense is a single USB/BT connection exposing multiple functions (not a
hub, but similar in feel):

| Function | Transport | How it's driven | Status in phidimus |
|----------|-----------|-----------------|--------------------|
| Buttons / sticks / touch / gyro | HID input report | `parse()` | ✅ works |
| LEDs / basic rumble motors / adaptive triggers | HID output report 0x02 | `write_feedback()` / blob passthrough | ✅ works |
| **Rich haptics / speaker / mic / headphones** | **Audio interface (PCM)** | audio stream to dedicated haptic channels | ❌ blocked over BT |

The rich haptics **are PCM audio**. The controller is one USB Audio Class device
with channels for headphone L/R, speaker, mic, and **two dedicated haptic
channels**. "Rich rumble" = audio played to those channels.

- **Over USB:** standard USB Audio Class (documented by the USB-IF; Sony-specific
  channel mapping). Reachable on PC — DSX drives rich haptics this way over USB.
- **Over Bluetooth:** the haptic audio rides a **Sony-proprietary protocol** the
  PS5 console speaks. PC Bluetooth stacks don't, so DualSense rich haptics
  **don't work over BT on PC even natively.** The "sound card" is there; there's
  no driver for it on the BT side.

## Options to replicate it faithfully (all hard)

1. **Reverse-engineer Sony's BT haptic protocol.** Capture PS5↔controller BT
   traffic, decode it, build a USB-audio → BT-haptic converter.
   *Blocker:* the PS5↔DualSense BT link is **encrypted/authenticated** — you
   can't sniff it without the link key / breaking BT crypto first. Research-grade.
2. **Force the controller to expose its USB-audio protocol over BT** (undocumented
   mode command, or custom controller firmware) so the documented USB Audio Class
   path applies wirelessly. *Blocker:* may not exist; custom firmware is a project
   in itself (signed/encrypted firmware to dump+rebuild).
3. **Use Sony's official PS5 SDK / dump+decompile the firmware.** *Blocker:*
   license/IP — kills open-source/public distribution; firmware is signed.

4. **Capture at the source on a jailbroken PS5 (most viable faithful path).**
   Sniffing the air fails because of link-layer encryption — but that crypto
   happens *in the BT controller chip*. Hook **above** it on a hacked PS5 and the
   data is plaintext:
   - **Best hook = HCI layer** (data the PS5 host stack hands its BT chip): you
     get the exact L2CAP/profile payload going to the controller, in the clear —
     i.e. the BT haptic wire format directly, skipping the USB→BT conversion
     guesswork.
   - **Higher hook** (haptic/audio engine) gives the PCM samples — one step
     further from the wire.
   - **Hybrid:** a jailbreak may let you extract the pairing **link key**, then
     decrypt BT air-traffic captured normally (no live hook).
   *Constraints:* needs a PS5 on an exploitable firmware kept offline. Legally
   cleaner than #3 — behavioral reverse-engineering for interoperability, not
   copying Sony source. Still a real project, but the only faithful route that
   doesn't require defeating BT crypto.

## The architectural reality

Faithful rich haptics essentially **require USB**. But phidimus's value in the
ps5→ps5 case is the **BT → virtual-USB bridge** (use the pad wirelessly for a
USB-only game). So rich haptics and this wireless use case are *inherently* at
odds on PC — the limitation isn't a phidimus bug, it's the same wall every PC
tool hits with a BT-connected DualSense.

## The pragmatic path (works today, no reverse engineering)

**Down-convert the haptic audio to the basic rumble motors** (which DO work over
BT). Not faithful, but a usable approximation — roughly what DSX does. This is
where the **"MIDI → rumble" test idea** fits: a simple way to feed the
audio→rumble converter without hand-authoring rumble packets. Would require
emulating the audio interface on the virtual USB device (to receive the game's
haptic-audio stream) + an envelope/amplitude → motor-intensity mapping.

Parked for now. Everything else in the DualSense passthrough works.
