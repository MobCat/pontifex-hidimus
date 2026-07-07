# Buildroot image — kernel & package changelog

What the Pontifex Hidimus Pi image **adds**, **removes**, and deliberately **keeps**
relative to the stock Buildroot `raspberrypi3_64_defconfig` base — and *why*.

**Use this before adding a phidimus feature.** If a new feature needs a kernel
option, driver, library, or daemon, check the **Removed/Disabled** list first — we
may have cut it for boot speed/size, and re-enabling is usually one line. The
**Re-add if needed** section lists things we anticipate wanting back.

Everything here lives in the `BR2_EXTERNAL` tree at `image/buildroot/`. The source
of truth is the fragments — keep this doc in sync when you change them:

| Area | File |
|---|---|
| Required kernel options | `board/phidimus/zero2w/kernel/required.fragment` |
| Boot-speed/size trims | `board/phidimus/zero2w/kernel/trim.fragment` |
| WiFi kernel options | `board/phidimus/zero2w/kernel/wifi.fragment` |
| Packages / userspace / firmware | `configs/phidimus_base.fragment` (+ `_dev` / `_prod`) |
| Firmware-side / boot | `board/phidimus/zero2w/config.txt`, `cmdline.txt` |

Base: **`raspberrypi3_64_defconfig`** (64-bit aarch64, prebuilt Bootlin toolchain),
DTB overridden to `bcm2710-rpi-zero-2-w` (we run a Pi 3 64-bit build on the Zero 2 W).

---

## Added

### USB gadget stack — the core of the product
The dongle *is* a USB controller to the host, so we pull in the full gadget stack
to control the raw USB output at a low level:
- `USB_GADGET`, `USB_DWC2` + `USB_DWC2_DUAL_ROLE` — the dwc2 controller in
  peripheral mode (config.txt `dtoverlay=dwc2,dr_mode=peripheral`).
- `USB_LIBCOMPOSITE`, `USB_CONFIGFS`, `USB_CONFIGFS_F_FS`, `USB_F_FS` — FunctionFS,
  the userspace-owned HID/vendor gadget path (testpad…ps5 work over this).
- **`USB_RAW_GADGET`** — the reason this custom image exists. FunctionFS can't carry
  vendor/XInput descriptors (Xbox 360, OG Xbox, DS3 — their odd `0x21` descriptors);
  raw-gadget hands every setup packet to our `usbdev.Device`, exactly like USB/IP.
  **Absent from stock Pi OS** → the original blocker.
- **`USB_CONFIGFS_MASS_STORAGE`** (+ `USB_F_MASS_STORAGE`) — the **USB Drive mode**
  gadget (phidimus-pi `Mode > USB Drive`): exposes the PHIDIMUS data partition to a
  host PC as a plain USB drive so configs/modules/the app binary update over USB,
  no SD pull, no OS rebuild. The ONE-TIME kernel add that unlocks rebuild-free app
  iteration. See [usb-drive-mode.md](usb-drive-mode.md).
- `CONFIGFS_FS` — the gadget control plane (`/sys/kernel/config`; mounted via fstab).

### Controller input + "own the pads"
- `UHID` — **critical for BT input**: BlueZ creates a paired controller's hidraw
  node via `/dev/uhid`. Without it there is *no* BT controller input at all.
- `HID`, `HID_GENERIC`, `HIDRAW`, `USB_HID` — our raw HID read path (USB + BT).
- bluez **HID/HOG plugins** (`BLUEZ5_UTILS_PLUGINS_HID/_HOG`) — turn a bonded
  BT-Classic/LE HID controller into an input device via uhid. Without these the
  adapter scans but a controller won't pair/connect.

### Bluetooth
- BT stack: `BT`, `BT_BREDR`, `BT_LE`, `BT_RFCOMM`, `BT_BNEP`, `BT_HCIUART` (=**m**,
  see note in Removed), `BT_HCIUART_BCM`, `BT_HCIUART_SERDEV`, `SERIAL_DEV_BUS`
  (krnbt attaches the BCM43430B0 over PL011).
- `RFKILL` — BT boots soft-blocked; we self-unblock via `/dev/rfkill`.
- BT pairing crypto: `CRYPTO_CMAC`, `CRYPTO_ECDH`, `CRYPTO_ECC`, `CRYPTO_AES`(+ARM64),
  `CRYPTO_USER_API_HASH`/`_SKCIPHER` (af_alg) — SSP/LE pairing fails without them.
- `bluez5_utils` (+ client/experimental), `dbus`.

### WiFi (capability in both images; not brought up at boot)
- `CFG80211`, `MAC80211`, `BRCMFMAC` (=**m**), `BRCMUTIL`, SDIO host (`MMC*`).
- Userspace `wpa_supplicant` + `iw` are **dev-image only**.

### Firmware (real Buildroot package — no manual blobs)
- `brcmfmac_sdio-firmware-rpi` (+`_BT` + `_WIFI`) — ships the BT `.hcd` (incl. the
  synaptics blob) and the brcmfmac WiFi NVRAM for the onboard combo chip.

### Panel / HAT
- `SPI`, `SPI_BCM2835`, `SPI_SPIDEV` (SH1106 OLED), `GPIOLIB`, `GPIO_CDEV`
  (joystick + keys + BOOT-fix line), `I2C`/`I2C_BCM2835` (future I2C panels).

### Introspection
- `IKCONFIG` + `IKCONFIG_PROC` — `/proc/config.gz` (stock had it off).

### Image layout (not kernel)
- 3rd **FAT32 "PHIDIMUS" data partition** holding `phidimus-pi` + config/modules/
  macros + logs; **RAM-loaded** so the binary is swappable without a rebuild.

---

## Removed / Disabled

### Display / GPU / video (the dongle is headless; OLED is SPI, not DRM)
- `DRM`, `DRM_VC4`, `FB`, `BACKLIGHT_CLASS_DEVICE`, `MEDIA_CEC_SUPPORT`.
- config.txt: no `vc4-kms-v3d`, `display_auto_detect=0`, `gpu_mem=16`.

### Audio — **HDMI/onboard audio** (the Pi's own speakers, never used)
- `SOUND`, `SND` (and `snd_bcm2835`/HDMI codec via config.txt not loading audio).
- Note: controller-side audio (PS5/PS4 speaker, mic, **rich haptics**) is *not* this
  — that's a future USB-gadget UAC function (see Re-add).

### Camera / capture
- `MEDIA_SUPPORT` (V4L2, `bcm2835_v4l2`/isp, videobuf2, camera_auto_detect off).

### Specialised controller HID drivers — phidimus owns the pads
Disabled so the kernel never claims a *physical* controller (we read it raw via
hidraw and bind the *virtual* side to native host drivers):
- `HID_PLAYSTATION` (DualSense/DualShock — also frees the DualSense **output**
  channel for us), `HID_SONY` (DS3/DS4), `HID_NINTENDO` (Switch), `JOYSTICK_XPAD`
  (Xbox), `JOYDEV`. We keep **only** `HID_GENERIC`.

### Networking boot-wait — no Ethernet on the Zero 2 W
- `BR2_SYSTEM_DHCP=""` (was `"eth0"`). The Pi Zero 2 W has **no Ethernet port**, so
  the stock boot-time `ifup`/DHCP on `eth0` just sat there timing out — pure wasted
  boot time. This single change cut boot from ~1 min to ~8 s. WiFi is brought up on
  demand, not at boot. (We did not strip Ethernet *drivers* from the kernel — they
  inherit from the base defconfig and cost nothing if no NIC exists.)
- PXE / network boot isn't configured or used — the Pi boots from the SD card — so
  there's nothing netboot-specific to disable; the only Ethernet-related cost was the
  `eth0` DHCP wait above.

### Appliance trim (size/boot)
- `ZRAM`, `FUSE_FS`, `IPV6`, `BINFMT_MISC`.

### Bluetooth-on-mini-UART
- config.txt: **no** `dtoverlay=miniuart-bt`; cmdline has **no** `console=ttyAMA0`.
  We keep BT on the high-quality PL011 (matches the fingerprinted stock board);
  consequently there is no serial console on that UART.

---

## Kept (deliberately, though one might assume otherwise)

- **The full inherited kernel module set.** We did *not* aggressively trim the
  hundreds of `=m` drivers the RPi defconfig builds. Those modules don't load unless
  used, so they cost **rootfs size, not boot time** — and boot time was the goal.
  (If image size ever matters, that's the lever; boot speed lives in init/services.)
- **WiFi in production**, not just dev — the BCM43436 is a WiFi+BT combo chip and we
  want the capability available; prod just doesn't run a WiFi daemon at boot.
- **`BT_HCIUART` as a module, not built-in.** Firmware-needing drivers *must* be
  modules here: built-in, they probe before the SD rootfs (with `/lib/firmware`) is
  mounted → `request_firmware` fails `-2`. `S05modules` modprobes them after mount.
  Same reason `BRCMFMAC` is `=m`. **General rule: any driver whose firmware lives on
  the rootfs must be `=m`.**
- `configfs`, `IKCONFIG_PROC`, the BT pairing crypto — small, and needed.

---

## Re-add if needed (anticipated future features)

| Want to add… | Re-enable | Notes |
|---|---|---|
| **PS5/PS4 audio, mic, rich haptics** to the host | `USB_F_UAC1`/`UAC2` (USB gadget audio) | The controller-audio path; pairs with userspace moving PCM over BT. NOT the Pi's HDMI audio we cut. |
| **Video-receiver controller** (Wii U GamePad / PS Portal idea) | `VIDEO_BCM2835_CODEC` (HW H.264, V4L2 M2M) only | The ONE "video" module worth re-adding — a userspace ffmpeg pipeline using the HW codec, *not* the DRM/display stack. |
| Proper **WiFi regulatory domain** | `wireless-regdb` package | Currently world domain; the `regulatory.db ... -2` dmesg line is benign without it. |
| **BT debugging** (btmon/btattach/hcitool) | `BLUEZ5_UTILS_TOOLS` (+`_DEPRECATED`) | Handy once there's console/USB-serial access. |
| **xbox360 / OG Xbox / DS3 output that actually sends input** | already have `USB_RAW_GADGET=y` | Kernel side is ready; the raw-gadget *backend* in `internal/usbgadget` is the remaining work (FunctionFS can't carry their descriptors). |
| **DS3 (and similar) that need a driver init handshake** | the QC module must own it | We disabled `HID_SONY` etc., so any activation magic the kernel driver used to do (DS3 `set_operational`) must move into the QC module. |
