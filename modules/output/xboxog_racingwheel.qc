// Xbox Original Racing Wheel (XID) — usb_device output module.  *** DRAFT 0.1.0 ***
//
// An experiment, not a finished device. Purpose: find out WHY Colin McRae Rally
// 2005 drives force feedback down the EP0 `SET_REPORT` path (which wedges the Pi's
// dwc2 controller) instead of the robust interrupt-OUT endpoint every other game
// uses — see docs/xbox-og-controller.md → "Force feedback over EP0". The theory is
// that the game routes FFB by DEVICE IDENTITY: present as the wheel and it may drive
// force over the interrupt-OUT endpoint (which never wedges), curing the freeze.
//
// Like the Duke, this IMPORTS the Controller S module (xboxog_rawusb.qc) for all the
// real work — declare_signals, pack, on_output, on_control — and overrides ONLY the
// identity. So the 20-byte report, the rumble/force decode, and the capability
// answers all come from the S module unchanged; only the USB identity below differs.
//
// ── What we KNOW (captured from a real 3rd-party OG Xbox wheel, standard USB
//    descriptors only — an lsusb dump the user found; NOT our capture): ──────────
//   idVendor    0x3767   (3rd-party, not Microsoft's 0x045E)
//   idProduct   0x0101
//   bcdDevice   0x0280   (2.80)
//   bMaxPacketSize0 8    (same as the Controller S)
//   Interface   58 / 42 / 00  (XID — identical class to the controller)
//   IN endpoint 0x82, interrupt, 32 B, 4 ms   (like the Duke, not the S's 0x81)
//   OUT endpoint 0x02, interrupt, 32 B, 4 ms   (SAME interrupt-OUT the pad has)
//
// ── What we DON'T know yet (needs a real wheel + `phidimus-sdk --usb --ctrl` to
//    fetch the vendor XID blob, which lsusb can't read): ────────────────────────
//   * the XID descriptor's bType / bSubType — a wheel almost certainly reports a
//     DIFFERENT subtype than a gamepad, and that subtype is the most likely field
//     the game reads to decide "wheel". We keep the CONTROLLER's XID here (bType 1,
//     bSubType 2) so the device still enumerates cleanly; if presenting the wheel's
//     VID/PID alone does NOT change the FFB routing, the real subtype is the next
//     thing to capture and try.
//   * the wheel's real input/output report FORMAT (a wheel + its analog pedals almost
//     certainly use a bigger, differently-laid-out report than the 20-byte pad one).
//     We keep the pad's report so the wheel is at least drivable for the test.
//
// So this draft is a clean way to answer ONE question on hardware — does the wheel's
// USB identity move Colin McRae's FFB off EP0? — without needing the physical wheel.
// Watch the channel with log_transport_frames: interrupt-OUT (handle=3) = cured;
// still `ep0 OUT` = identity isn't the lever and we need the real XID capture.

import "xboxog_rawusb.qc"

string MODULE_ID      = "xboxog_racingwheel";
string MODULE_NAME    = "Xbox Original Racing Wheel (virtual USB / XID) [DRAFT]";
string MODULE_VERSION = "0.1.0";

int    USB_VID        = 0x3767;   // 3rd-party wheel vendor (not Microsoft)
int    USB_PID        = 0x0101;
int    USB_BCD_DEVICE = 0x0280;   // 2.80
// USB_EP0_SIZE stays 0x08 (inherited from the Controller S) — matches the wheel dump.

void() declare_usb =
{
    // Same XID config as the Controller S, but the interrupt-IN endpoint is 0x82
    // (the one config-descriptor byte that differs on the wheel — same as the Duke).
    // The interrupt-OUT endpoint 0x02 is unchanged: it's the channel we WANT the game
    // to send force on (it never wedges), so it must be present and correct.
    usb_config(
        "09 02 20 00 01 01 00 80 32"   // configuration: 1 interface, bus-powered 100 mA
        "09 04 00 00 02 58 42 00 00"   // interface 0: class 58/42/00 (XID)
        "07 05 82 03 20 00 04"         // EP 0x82 IN,  interrupt, 32 B, 4 ms
        "07 05 02 03 20 00 04"         // EP 0x02 OUT, interrupt, 32 B, 4 ms
    );

    in_endpoint(0x82);    // pack() reports go out here (0x82, like the Duke)
    out_endpoint(0x02);   // console force/rumble arrives here -> on_output() (inherited)
};

// NOTE: on_control() is NOT overridden — the wheel's real XID descriptor (subtype /
// report sizes) is unknown, so we inherit the Controller S's known-good XID answers so
// the device enumerates. Once a real wheel is captured, override on_control() here with
// the wheel's bSubType and capability reports (Duke shows the override pattern).
