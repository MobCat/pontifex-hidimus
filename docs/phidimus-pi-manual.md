# phidimus-pi manual (v4.x — DRAFT)

The dongle. This is the reference for **phidimus-pi**: the Raspberry Pi build that
runs the whole Phidimus engine natively and turns a Pi Zero 2 W / CM4 into a
plug-in controller converter, driven entirely from the OLED HAT — no PC, no SSH.

> **Draft status.** This is a first pass covering the 4.x feature set so we can see
> what's actually here and what every config option does. It's an ongoing project;
> some sections are thin or marked TODO. Revisit for a proper cut at v5.0.0. The PC
> SDK, the QC module API, and the profile-authoring deep-dives live in the other
> docs (see [Related docs](#related-docs)); this file is the *device* manual.

---

## What it is

Drop your `.qc` modules and one profile `.ini` onto the data partition, plug it in,
and the Pi presents itself to the host (PC or console) as a real USB controller —
the conversion is invisible to whatever it's plugged into. Same engine as the PC
SDK; the difference is the transport (a real USB gadget instead of USB/IP) and the
front-end (an OLED menu instead of a CLI). See [architecture.md](architecture.md)
for the engine model.

### Build flavours (compile-time, not a flag)

There are two builds, chosen at compile time (`build-pi.sh` emits both):

| Build | Path | Debug menu | Logging |
|-------|------|-----------|---------|
| **prod** (default) | `build/pi/prod/phidimus-pi` | hidden | quiet; 2 logs, wiped per boot |
| **dev** (`-tags dev`) | `build/pi/dev/phidimus-pi` | shown | verbose; numbered logs kept per boot |

To switch on hardware, drop the other binary in over **USB Drive mode** and reboot —
no args, no reconfigure. Verbose logging and the Debug menu ride along with the dev
binary.

---

## The data partition (`/data`)

The binary and all user data live on the FAT **PHIDIMUS** partition, mounted at
`/data` and editable on a PC over [USB Drive mode](#usb-drive-mode). Layout:

```
/data/
├── phidimus-pi          ← the binary (RAM-loaded at boot; swap + reboot to update)
├── phidimus.ini         ← device settings (this file's [options]/[devices]/[debug])
├── config/              ← profile .ini mapping files (browsed in the Configs menu)
├── modules/             ← input/output .qc modules
├── macros/              ← macro .qc modules
└── logs/                ← per-run app + boot logs
```

The working directory at runtime is `/data`, so every relative path in a profile
(and `phidimus.ini` itself) resolves here.

---

## The OLED menu

A persistent 2-line header sits on every screen (brand + engine version, and a
controller/status readout on the right — see [Status bar](#status-bar)). Navigation:

- **Joystick Up/Down** — move the selection
- **PRESS or KEY2** — enter / select
- **KEY1** — back
- **KEY3** — context action (e.g. *forget* a paired device)

Menu tree (prod; dev adds **Debug** before Power and a fuller Power menu):

```
Main
├── Running:/Last:/(no recent config)   ← quick-launch the last profile
├── Devices ─── Bluetooth ── New       ← scan + pair a new controller
│   │           └────────── Paired     ← connect / disconnect / forget
│   └── USB                            ← list hidraw nodes (multi-USB boards only)
├── Configs                            ← file browser over config/, select an .ini to run
├── Mode ────── USB Drive              ← expose /data to a host PC
│   └───────── Direct Connect          ← BT→PC-SDK bridge (coming soon)
├── Debug (dev only)                   ← Ver/IP, button/screen/feedback tests
└── Power ───── Sleep pi               ← low-power idle (see Sleep)
    ├───────── Reboot pi
    └───────── Shutdown pi
              (dev also: Restart/Shutdown pi-app)
```

On a single-USB-port board (Pi Zero family) the lone port *is* the output gadget,
so USB input is impossible; **Devices** skips straight to the Bluetooth menu.

### Status bar

The header's right block reads `<conn> <charge><level>` plus a running `*`:

- **conn** — `B` Bluetooth connected (polled from BlueZ, shows even with no profile
  running). `U`/`W` reserved for future USB-host / wireless input.
- **charge** — `+` charging, `-` discharging, `?` unknown.
- **level** — `N/M` (raw level/max) or `?`.
- **`*`** — a profile is running; blinks on input activity.

With nothing connected and nothing running it falls back to the full brand + version.

---

## `phidimus.ini` — device settings

The dongle's own settings file (distinct from a **profile** `.ini`, which is a
mapping config — see [Profile configs](#profile-configs-the-mapping-ini)). It's
seeded with documented defaults on first boot and editable over USB Drive mode.
Three sections:

```ini
# phidimus-pi main user options

[options]
# last_config   : last profile run — shows as "Last:"/"Running:" on the main menu (set automatically).
# sleep_timeout : minutes idle on the Main menu before auto-sleep. 0 = never. Default 10.
last_config = config/pc/ps5_bt_to_usb_rapidfire.ini

# Paired Bluetooth devices. Rename the right-hand side to a name you'll recognise.
[devices]
A0:FA:9C:C9:47:AA = Perl ps5 ds

# [debug] gates which logs are kept on the SD card (absent = on, the default).
[debug]
log_phidimus-boot = false
log_phidimus-pi = true
log_transport_frames = false
log_host_port = false
```

### `[options]`

| Key | Default | Meaning |
|-----|---------|---------|
| `last_config` | — | Path of the last profile run; set automatically, shown as *Last:/Running:* on the main menu. |
| `sleep_timeout` | `10` | Minutes idle on the Main menu before [auto-sleep](#sleep). `0` = never auto-sleep (manual Sleep still works). |

### `[devices]`

Friendly names for paired Bluetooth controllers, keyed by MAC (`AA:BB:…= name`).
Seeded automatically from BlueZ the first time a paired pad is seen; rename the
right-hand side to whatever you like — it drives the name shown in the BT menus.

### `[debug]`

Gates which logs are kept on the SD card, and the home for dev-only tuning options.
**Absent file / section / key = ON** (the default) — an unconfigured dongle logs
everything.

| Key | Default | Meaning |
|-----|---------|---------|
| `log_phidimus-boot` | `true` | Keep the per-boot diagnostics log (S98diag). Turn off once the OS image is stable; turn back on when the image changes. |
| `log_phidimus-pi` | `true` | Keep the main app log. Off → app log goes to `/dev/null` (nothing on the card). |
| `log_transport_frames` | `false` | The high-volume per-report data-frame dumps (`host report`/`on_output`) crossing a transport (USB gadget; BT later) → its **own** `NNN_phidimus-transport.log`. Off keeps the event timeline readable; on for wire-level frame debugging (rumble bytes, etc.). |
| `log_host_port` | `false` | The host-facing USB-port chatter — enumeration/control transfers, and the future "which console port are we on" probe — → its **own** `NNN_phidimus-host.log`, kept out of the app log so a per-port trace can be diffed. |

Both extra logs write to their **own** per-run file (so neither ever clutters the app
log); unknown `[debug]` keys are preserved across saves, so this section is also where
future dev-only options land.

---

## Logging

Logs live on `/data/logs` (FAT → readable over USB Drive mode). The Pi has **no
RTC**, so every boot's timestamps restart at `00:00`; to keep boots distinguishable
each run gets its own file pair, with the run number **first** so a run's files
group together:

```
prod : phidimus-pi.log        + phidimus-boot.log        (WIPED fresh every boot)
dev  : NNN_phidimus-pi.log     + NNN_phidimus-boot.log    (NNN++ each boot, old kept)
       (+ NNN_phidimus-host.log       when log_host_port is on)
       (+ NNN_phidimus-transport.log  when log_transport_frames is on)
```

A log gated off in `[debug]` is simply absent for that run — an obvious gap next to
its siblings (`029_phidimus-pi.log` present, `029_phidimus-boot.log` missing = boot
log was off for run 29). The four streams:
- **app** (`phidimus-pi`) — the main engine log / event timeline (always, unless gated).
- **boot** (`phidimus-boot`) — S98diag's early diagnostics adopted under the run's name.
- **host** (`phidimus-host`, `log_host_port`) — the host's USB enumeration/control-transfer
  chatter on its own, so a trace can be captured per console port and diffed.
- **transport** (`phidimus-transport`, `log_transport_frames`) — the high-volume per-report
  data frames (rumble/LED OUT reports, `on_output`) on their own, so turning them on for a
  wire capture never floods the app log.

---

## Bluetooth

Pairing and management are done from **Devices → Bluetooth**:

- **New** — active scan; ENTER pairs + connects + trusts a discovered controller.
- **Paired** — ENTER connects (or disconnects) a saved pad; KEY3 forgets it (with a
  confirm). A paired pad is *Trusted*, so it auto-reconnects when powered on.

Connecting a paired pad retries across a window, so "press Connect, then turn the pad
on" works. Once a device shows connected, its hidraw node is up and a BT profile can
run against it (e.g. `config/pc/ps5_bt_to_usb.ini`). See
[project-next-bluetooth-input] notes and [DualSense-USB-vs-BT.md](DualSense-USB-vs-BT.md).

---

## Sleep

A low-power idle state (not a shutdown) for a dongle left plugged in and unused:
OLED off, onboard ACT LED off, Bluetooth soft-blocked, CPU governor → `powersave`,
menu loop parked. **KEY2 wakes it** (only KEY2). Auto-sleep fires after
`sleep_timeout` minutes idle **on the Main menu with no profile running** (a running
profile owns the radio/USB, so it blocks sleep and logs why); a Power-menu **Sleep**
item requests it manually. The Zero 2 W has no working suspend-to-RAM, so this is
governor + parked loop, not a kernel suspend — the OLED and radio off are the real
savings.

---

## USB Drive mode

**Mode → USB Drive** exposes `/data` to a host PC as a USB mass-storage drive so you
can update configs/modules/macros/`phidimus.ini`/the binary without reflashing the
image. Entering the mode stops the engine and releases `/data` from the Pi (a FAT
partition can't be mounted rw on the Pi and served to the host at once); leaving it
reclaims `/data`. See [usb-drive-mode.md](usb-drive-mode.md).

Exit keys (shown on the locked USB-Drive screen):

- **K1** — done: reclaim `/data`, back to the menu (for a config/module edit).
- **K3** — done + reboot: reclaim `/data`, then reboot (RAM-loads a replaced
  `phidimus-pi` binary cleanly).

**Secret exit — Down + K3 (dev build only, not shown on-screen).** Hold the joystick
**Down** while pressing **K3** to reclaim `/data`, **delete this run's per-run logs**,
and **power the Pi off** (not reboot). It exists for the bench cycle "plug in over USB,
edit/read files, unplug, shut down ready to move to real hardware": those edit-only
runs otherwise leave a trail of tiny throwaway `NNN_phidimus-*.log` files. It is
deliberately undocumented on the screen because it **discards logs** — use it only when
you know this run's log is noise. It is dev-only: the prod build keeps a single
wiped-per-boot log, so there is nothing per-run to clean up.

---

## Profile configs (the mapping `.ini`)

A **profile** is the input→output mapping config the engine runs (in `config/`),
distinct from `phidimus.ini` above. Profiles are pure data — signal name → signal
name with simple transforms; anything stateful/conditional goes in a `.qc` module or
macro. Full authoring guide + examples are in the [README](../README.md); this is the
option reference as the code parses it today.

### `[config]`

| Key | Meaning |
|-----|---------|
| `id` | Profile name (defaults to the filename stem). |
| `author` | Optional credit, shown in the startup log. |
| `phidimus` | Engine version the profile targets. Patch ignored; minor mismatch warns; a newer **major** than the engine is refused. |
| `input` | Input module id(s), comma-separated for simultaneous slots (e.g. `ps5ds` or `ps5ds, keyboard_input`). A monolithic module (e.g. `ps5ds`) handles USB/BT internally. |
| `output` | Output module id(s), comma-separated (ordered; a minimal target uses the first). |
| `macro` | Macro module id(s) to load (bound in `[defaults]`/`[<macro>.macro]`). |
| `method` | Output transport on hardware: `usb_ip`, `usb_gadget`, or `raw_gadget`. Empty = `usb_ip`. Off-hardware always falls back to USB/IP, so the profile stays portable. |
| `usbip` | USB/IP listen+attach `host:port` for USB/IP output (e.g. `0.0.0.0:3240` to serve over LAN). Ignored on the gadget transports. |
| `max_input_poll_hz` | Cap input reads/sec. `0` = unlimited. |
| `max_output_poll_hz` | Cap output writes/sec. `0` = unlimited (write after every input). |

### `[<output>.buttons]` — `FROM = TO`

Maps an input signal to an output button. Options (after a comma):

| Option | Default | Meaning |
|--------|---------|---------|
| `threshold` | 128 | Only for an **analog** input mapped to a button: press fires when the value (0–255) crosses this cutoff. Ignored for already-digital signals. |

Digital→digital button maps stack (OR). Prefix `MOD+FROM` / `!MOD+FROM` for a
[modifier guard](#modifier-guards).

### `[<output>.axes]` — `FROM = TO`

| Option | Default | Meaning |
|--------|---------|---------|
| `invert` | false | Flip direction. |
| `deadzone` | 0 | Inner fraction (0–1) treated as zero. |
| `sensitivity` | 1.0 | Curve exponent (2.0 quadratic, 0.5 sqrt). |
| `in_min`/`in_max` | module range | Override input range. |
| `out_min`/`out_max` | module range | Override output range. |

Also supports `MOD+`/`!MOD+` guards.

### `[<output>.feedback]` — `FROM = TO`

Routes rumble/haptic values from the output device back to the input device.

| Option | Meaning |
|--------|---------|
| `scale` | Linear multiplier before the curve. |
| `curve` | `linear` / `sqrt` / `square` / `natural` intensity shaping. |
| `map` | `map=[in:out, …]` interpolated lookup table (overrides scale/curve). |

### `[<output>.defaults]`

Resting axis values (`axis = value`) seeded into every frame for any axis a mapping
doesn't drive — e.g. a synthetic `BATTERY_LEVEL` for a macro-driven self-test.

### `[<input>.feedback]` — `TARGET = SOURCE`

Drives the **input** device's own feedback signals (LEDs, etc.) from a live input
signal through an interpolated `map=[in:out, …]` table — e.g. the DualSense lightbar
from `BATTERY_LEVEL`. Routes by signal name; nothing device-specific in the engine.

### `[defaults]`

Startup state applied once before the live loop:

- `macro = m.fn()` — run macro function `fn()` every frame from load (always-on).
- output button names / `axis = value` — initial pressed/axis state.
- input feedback (`LED_R = …`) — initial LED/lightbar/mic state.

### `[<macro>.macro]`

Binds macro functions to triggers: `BTN = fn(arg)` runs while `BTN` is held;
`BTN:press` / `BTN:release` fires once on that edge (latches/toggles).

### Modifier guards

Prefix any button/axis map's left side with `MOD+` (apply only while `MOD` is held)
or `!MOD+` (only while it is *not* held). Shift layers as config data, not module
logic. `MOD` is any button the input module reports.

---

## Related docs

- [architecture.md](architecture.md) — the engine model (device vs signals, transport, macros, handshakes)
- [README](../README.md) — profile authoring, transforms, macros, the binaries
- [QC_USB_API_v4.md](QC_USB_API_v4.md) — the QC module API (input + output)
- [usb-drive-mode.md](usb-drive-mode.md) — updating the dongle over USB
- [roadmap.md](roadmap.md) — what's done / planned across engine, dongle, modules
- [buildroot-changelog.md](buildroot-changelog.md) — the OS image

## TODO for the full manual (v5.0.0)

- Bench setup / first flash + the Buildroot image relationship.
- Feedback bars + running-screen readout, per-signal.
- Direct Connect (BT→SDK bridge) once built.
- WiFi configuration once the config path lands.
- A worked end-to-end example (pair a pad → pick a profile → play), with photos.
