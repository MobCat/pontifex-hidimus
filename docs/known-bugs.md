# Pontifex Hidimus — known bugs & parked issues

Bugs and limitations we understand but have **not fully fixed** — usually because the real
fix is blocked on hardware we don't have yet, or on a device we can't capture. Each entry
records what it is, the current mitigation (if any), and what a real fix would take.

This is deliberately separate from [roadmap.md](roadmap.md): the roadmap is forward work we
intend to do; this is *standing* behaviour a user might hit, with a documented status. A
`[parked]` item lives here, not on the active roadmap.

Status tags: **[parked]** blocked/deferred, mitigated or accepted · **[hotfixed]** a
mitigation is shipped that makes it survivable but isn't the true fix · **[open]** no
mitigation yet.

---

## [parked] [hotfixed] OG Xbox: Colin McRae Rally 2005 mid-race freeze (EP0 force-feedback wedge)

**Symptom.** Playing **Colin McRae Rally 2005** on a real original Xbox through the dongle
(`ps5_to_ogxbox_rawusb` and friends), the game freezes mid-race with the controller stuck
vibrating. With the mitigation below it no longer stays frozen — you get a brief (~¼ s)
"reconnect controller" flash and drop back to the pause menu, then carry on.

**Root cause — a `dwc2` hardware/driver race, below our code.** This one game drives force
feedback as a **HID `SET_REPORT` on EP0** (`0x21/0x09 wValue=0x0200`, payload `00 06 V V V V`
= a mono force magnitude), a steady ~25/s, instead of the interrupt-OUT endpoint every other
game uses. Sustained EP0-OUT control writes eventually wedge the Pi's dwc2 USB device
controller:

```
dwc2 3f980000.usb: dwc2_hsotg_ep_stop_xfr: timeout DOEPCTL.EPDisable
```

Every subsequent EP0 read then returns `EBUSY`, the console blocks on the unanswered transfer,
and the game freezes. It is a **race, not overload** — identical 25/s load wedges anywhere from
6 s to 150 s apart. Confirmed independent of our logging (froze with logging on *and* off, off
sooner) and of our servicing speed (~40 ms of slack per report). The likely reason real
hardware never hits it: a real controller's own, much slower/simpler silicon doesn't expose the
race that the Pi's faster, general-purpose controller does. Full technical write-up:
[xbox-og-controller.md](xbox-og-controller.md) → "Force feedback over EP0".

**Why we don't just refuse the report.** Stalling the EP0 `SET_REPORT` stops the freeze, but
the game then sends **no force at all** — you lose rumble entirely (it does *not* fall back to
the interrupt-OUT endpoint). The decision is that **working rumble with a rare, self-recovering
dropout beats no rumble**.

**Mitigation shipped (the "hotfix").** On a *confirmed* wedge (a persistent `EBUSY` on the EP0
OUT read — never speculative), `recoverWedge` in
[internal/usbgadget/rawgadget_linux.go](../internal/usbgadget/rawgadget_linux.go) automatically
does what a manual profile-restart did: tear the gadget down and re-enumerate it in place — the
software equivalent of yanking the controller out and plugging it straight back in to clear the
stuck endpoint. It holds a ~100 ms settle so the console registers a clean disconnect. The
DualSense's Bluetooth link is untouched, so it stays paired. Every recovery is logged with the
real controller-gone time (`auto-recover COMPLETE — controller re-enumerated N ms after the
wedge`). Hardware-validated over a 34-minute session (log 064): 16 wedges, all recovered at a
steady ~244 ms, no console lock.

> Earlier note, now unconfirmed: a single hard console lock was seen once with a much faster
> (15 ms) re-bind, including a first-ever lock while sitting in a menu. It has **not** recurred
> at the 100 ms settle. Sample size 1; watch for it, don't assume it.

**Experiment that ruled out the easy fix.** We suspected the game routes FFB by device identity
— present as the racing wheel and maybe it uses the safe interrupt-OUT path. Tested on hardware
(log 001) with a draft `xboxog_racingwheel` presenting the real wheel's USB identity
(`3767:0101`, from a found lsusb dump), plus a Duke A/B. **Result: no change** — all three
(Controller S, Duke, wheel) still flooded EP0 and wedged; 0 of 23,123 force frames used the
interrupt-OUT endpoint. So the USB VID/PID/endpoint identity is **not** the lever. What we
*couldn't* test is the wheel's **XID descriptor subtype** (the draft keeps the controller's,
because a real wheel's XID can't be read without owning one) — that's the remaining candidate.

**What a real fix would take (why it's parked).** Two pieces of hardware we don't have:
1. **A real OG Xbox force-feedback wheel** (period candidate: Fanatec Speedster 3 ForceShock) to
   capture its real XID descriptor + report format with `phidimus-sdk --usb --ctrl`, and to see
   whether the game drives *it* over EP0 or the interrupt-OUT endpoint.
2. **A Pi build with USB-in *and* USB-out** to MITM-log the full host↔device pump end-to-end
   (the current Zero 2 W has a single USB data port, committed to output).

Until then: the freeze is hotfixed (auto-recover), the racing-wheel path is a
[roadmap](roadmap.md) draft, and this stays parked. Related memory:
force-feedback → DualSense **adaptive triggers** as a test destination is a follow-up config
idea once the above is unblocked.
