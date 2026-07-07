# References & credits

Pontifex HIDimus is built by MobCat, but it stands on a lot of prior open work 
protocol reverse-engineering, precedents that proved a thing was possible, and the
platform pieces the engine runs on. This file records what we leaned on and for what, so
credit is where it's due and future-us can find the source again.

The project ethos is **"capture reality, paste it"** most device knowledge here came
from capturing real hardware by us, but these projects and wikis are what made the captures
make sense. Format for each entry:

```
**[project title](link)** - Author of that project or code.
A small descriptor of what we used from here and why it's here.
```

---

## USB / transport

- **[usbip-win2](https://github.com/vadimgrn/usbip-win2)** - vadimgrn.
  The WHQL-signed Windows USB/IP client the desktop bench attaches the virtual controller
  through (no test-signing needed). Honours the custom `--tcp-port` we use for the
  `usbip = host:port` config key.
- **[VIIPER](https://github.com/Alia5/VIIPER)** - Alia5.
  A userspace USBIP virtual-input emulator; proved the "serve a USB device over USB/IP
  entirely from userspace, no custom kernel driver" concept that became the engine's own
  USB/IP server after ViGEm was removed.
- **[ViGEmBus](https://github.com/ViGEm/ViGEmBus)** - Nefarius Software Solutions.
  The virtual-gamepad kernel shim the project used *before* 4.0. Removed because it
  hardcoded the device identity and was locked to the XInput template; acknowledged here
  as the thing whose limits pushed us to own the whole USB layer ourselves.
- **[raw-gadget](https://github.com/xairy/raw-gadget)** - Andrey Konovalov (xairy).
  The Linux kernel raw-gadget interface (and examples) the dongle drives to present real
  USB devices byte-for-byte, the backend that carries vendor/non-compliant descriptors
  FunctionFS rejects. (The OG Xbox EP0-FFB freeze is a race in the Pi's dwc2 UDC under
  this path see [docs/known-bugs.md](known-bugs.md))

## Original Xbox (XID)

- **[ogx360](https://github.com/Ryzee119/ogx360)** - Ryzee119.
  The precedent that a bare XID controller is accepted by a real original Xbox with no hub
  and no controller authentication — the basis for `xboxog_rawusb`.
- **[Xbox Dev Wiki - Input Devices](https://xboxdevwiki.net/Xbox_Input_Devices)** - The Xbox homebrew community.
  Reference for the Xbox input device classes (gamepad, wheel, light gun, etc.) and the
  XID protocol, behind [docs/xbox-og-controller.md](xbox-og-controller.md) and the racing-wheel
  investigation.

## Xbox 360

- **[GP2040-CE](https://github.com/OpenStickCommunity/GP2040-CE)** - OpenStickCommunity.
  Reference for the Xbox 360 XSM3 challenge–response auth-passthrough approach,
  for the future "360 on a real 360" path.
- **[UsbdSecPatch](https://github.com/InvoxiPlayGames/UsbdSecPatch)** - InvoxiPlayGames.
  If we know how to disable XSM3, then we can better understand how to enable it.
- **[libxsm3](https://github.com/InvoxiPlayGames/libxsm3)** - InvoxiPlayGames.
  Handy little library for how to interface with XSM3 on real hardware.
- **[Reverse Engineering of Xbox Security Method 3](https://oct0xor.github.io/2017/05/03/xsm3/)** - oct0xor.
  Lots of usefull data about the raw data and bytes the XSM3 module sends between the contoler and cosnole
- **[Reverse Engineering of Xbox Security Method 3](https://github.com/oct0xor/xbox_security_method_3)** - oct0xor.
  More or less the same info as above, but on there github.
- **[Xbox 360 Controller Security](https://brandonw.net/360bridge/doc.php)** - brandonw.net.
  Contains a really good USB hardware analyzer log for the communication between the controller and console
  Gives us not only the byte data, but what order it happens in.
- **[OGX-Mini-2026](https://github.com/MegaCadeDev/OGX-Mini-2026/)** - MegaCadeDev.
  Another real world compleate project that implemnts XSM3.

## PlayStation controllers

- **[MissionControl](https://github.com/ndeadly/MissionControl)** - ndeadly.
  Nintendo Switch BT-host sysmodule; the authoritative reference for DS3 / DS4 / DualSense
  Bluetooth init + pairing (it confirmed our DS4 handshake and fixed the 0x11 report header
  bytes).
- **[joypad-os](https://github.com/joypad-ai/joypad-os)** - joypad-ai (formerly USBRetro).
  Apache-2.0 microcontroller controller-adapter firmware; a phidimus-pi reference and the
  DS4 VID/PID donor (capture-first still ruled).
  Also used the [controllertest.io](https://controllertest.io/) a lot in testing of controllers.
- **[SAxense](https://github.com/egormanga/SAxense)** - egormanga.
  Clean-room reverse-engineering of the DualSense's rich (audio-PCM) haptics, one half of,
  the enabler for the future raw-Bluetooth HD-haptics work.
- **[DS5Dongle](https://github.com/awalol/DS5Dongle)** - awalol.
  A productized DualSense HD-haptics bridge on the RP2350, the other half; shows the
  audio-PCM haptics working end to end. See
  [DualSense-rich-haptics-roadblock.md](docs/DualSense-rich-haptics-roadblock.md).
  And this roadblock is even less of a block now we have raw Bluetooth control with the pi dongle.
- **[TriggerEffectGenerator](https://github.com/Nielk1/TriggerEffectGenerator)** - Nielk1.
  Reference for the DualSense adaptive-trigger effect byte format, behind the "fake FFB ->
  trigger resistance" work in `ps5ds.qc`

## Platform (the dongle)

- **[Buildroot](https://buildroot.org)** - The Buildroot project.
  The base the phidimus-pi Pi Zero 2 W image is built from (see
  [buildroot-changelog.md](docs/buildroot-changelog.md)).
  We didn't need silly things like video card drivers, hdmi, Ethernet stack / pixy boot for this project.
  So rip out anything we don't need. Now the pi boots in 11 secs, not in a few mins after the target console has already fully booted and waiting for inputs.
  We also had issues like the default PlayStation controller driver in linux was overwriting our custom driver. So rip it out.
- **[BlueZ](http://www.bluez.org)** - The BlueZ project.
  The Linux Bluetooth stack the dongle drives over D-Bus for pairing and input.
- **[godbus/dbus](https://github.com/godbus/dbus)** - the godbus project.
  The Go D-Bus binding used to talk to BlueZ.
- **[golang.org/x/sys/unix](https://pkg.go.dev/golang.org/x/sys/unix)** - The Go project.
  The raw syscall / ioctl surface behind the raw-gadget, rfkill, and GPIO/SPI paths.
- **[Ebitengine](https://github.com/hajimehoshi/ebiten)** - Hajime Hoshi.
  The GUI toolkit for the desktop `phidimus-configurator`

## Inspiration

- **[QuakeC (Quake source)](https://github.com/id-Software/Quake)** - id Software.
  QuakeC The shape and spirit behind the engine's tiny from-scratch `.qc` module VM
  see [architecture.md](docs/architecture.md) for more on the "why QuakeC" note.
  Also see more about our changes and additions to QC in [QC_USB_API_v4.md](docs/QC_USB_API_v4.md)

---

*Know of something we used and missed here? It belongs in this list please let me know. Crediting the giants we stand on is very important for future projects that may stand on top of us aswell like we have done here.*
