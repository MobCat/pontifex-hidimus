# DualSense (PS5) — USB vs Bluetooth

The DualSense is the same controller over USB and Bluetooth, but the two
transports are *not* interchangeable at the byte level. USB is trivial to talk
to; Bluetooth needs to be tricked into believing a real PS5 is on the other end
before it will give you full-resolution input and the complete feature stack.

This doc records what we confirmed by hand (pcap analysis + `--hids` byte
poking). VID `054C` PID `0CE6` on both transports.

---

## The short version

| | USB | Bluetooth |
|---|---|---|
| Input report | `0x01`, 64 B, control data at `raw[1..]` | `0x31`, 78 B, **everything shifted +1** (`raw[2..]`); a `0x01` "compat" report until you talk back |
| Output report | `0x02`, 64 B, write and forget | `0x31`, 78 B → padded to 547 B, **needs CRC32** or it's silently dropped |
| Common block start | byte 1 | byte 2 (after the `0x10` Sony tag) — so all output offsets shift +2 |
| Effort to use | plug in, read/write | handshake into full mode, checksum every packet |

USB DualSense is ready to hack on. BT DualSense needs the work below.

---

## Bluetooth: the gotchas (each one cost us real debugging time)

### 1. The compat-mode trap
On BT connect the controller sends a short **10-byte report `0x01`** — minimal
buttons, no gyro/touch/battery — and keeps sending it until it receives its
first valid **output** report `0x31` from the host. Only then does it flip to
streaming full 78-byte input reports `0x31`.

Consequence: an input-only setup that never writes feedback stays stuck in
compat mode forever, and `parse()` (which drops anything that isn't `0x31`)
looks broken for no visible reason. **You must send one output report to wake
it into full resolution.** In phidimus this happens because `[defaults]`
triggers a `write_feedback()` at open.

### 2. The CRC32 or nothing
Every BT output report ends with a CRC32 over `0xA2 || report[0..73]`, stored
little-endian at bytes `[74..77]`. Standard CRC-32 (poly `0xEDB88320`). Get it
wrong and the **controller firmware silently discards the packet** — no error,
no LED change, nothing. This is the single biggest "why isn't it working" trap.
(`feedback_crc32_sony_bt()` does this for you.)

### 3. Two header layouts, one wrong byte ruins it
The BT output report has a `0x10` Sony tag at byte `[2]`; the common control
block starts at byte `[3]`, so every USB output offset shifts **+2** for BT.
(Some Windows hosts omit the tag and start the block at byte `[2]` instead —
the firmware accepts both. phidimus uses the tagged layout.)

We lost time on `valid_flag2`: it must land at byte `[41]` (tagged layout).
Writing it at `[43]` — a reserved byte — means `LIGHTBAR_SETUP_CONTROL_ENABLE`
never sets, so the lightbar handover never happens and the bar stays on
firmware control. Symptom: you can't change the lightbar colour over BT at all.

### 4. valid_flag1 is the same on both transports
Bit `0x10` = PLAYER_INDICATOR enable, bit `0x04` = LIGHTBAR, bit `0x01` =
MIC_LED — identical USB and BT. (An old theory that BT swapped these bits was
disproven by capture; sending `0x55` made the player LEDs respond.)

---

## LED quirks (apply to both transports)

These are firmware behaviours you **cannot** override, so don't waste effort
trying:

- **Mic LED pulse is baked in.** Value `2` = pulse; the controller firmware
  runs the pulse animation itself. You don't (and can't) drive your own pattern
  by updating the byte every frame. `0` = off, `1` = solid, `2` = pulse.
- **Player-LED brightness is global and quantised.** One byte sets brightness
  for *all lit player dots at once*: `0` = high, `1` = medium, `2` = low. There
  is no per-dot brightness.
- **Player LEDs are mirrored, not individual.** The bitmask *looks* like 5
  addressable dots, but the firmware enforces symmetry: bitmask `0x01` and
  `0x10` both light the **outer pair**, `0x02` the **inner pair**, `0x04` the
  **centre**. Confirmed by `--hids`: sending `0x01` lit *both* outer dots. So
  the real hardware capability is three pair-signals (OUTER / INNER / CENTRE),
  which is exactly what `ps5.qc` exposes.
- **Lightbar is separate** — its own 0–255 RGB channels, unrelated to the
  player dots, and needs the `valid_flag2` handover (gotcha #3) over BT.

---

## Diagnostic tip

Input report `0x31` byte `[42]` (BT) is an **output-report receive counter** —
it increments on every output report the controller receives, including ones it
later rejects for a bad CRC. Useful to confirm your packet is *arriving*, but it
does **not** tell you the packet was *accepted*. The LEDs/rumble are the only
real acceptance signal.

---

## Byte maps

See `modules/input/ps5.qc` for the authoritative, commented offset tables
(`parse()` for input, `write_feedback()` for output, both USB and BT paths).
The module is the source of truth; this doc is the "why".
