// Xbox Original Controller — "the Duke" — usb_device output module.
//
// The Duke is the big original launch controller; the Controller S is the smaller
// later revision. On the wire they are the SAME XID device except for five bytes,
// so this module imports the Controller S output (xboxog_rawusb.qc) for all the
// real work — declare_signals, pack, on_output — and overrides ONLY the bits that
// differ on a real Duke. Captured from a real Duke (045E:0202) with `--usb`:
//
//   PID          0x0202  (vs 0x0289 Controller S)
//   bcdDevice    0x0100  (vs 0x0121)
//   EP0 size     0x40    (the Duke's control endpoint is 64 bytes, vs the S's 8)
//   IN endpoint  0x82    (vs 0x81)
//   XID bSubType 0x01 = gamepad (Duke)  (vs 0x02 gamepad S)
//
// Import + override: the import pastes the S module's text here; every global and
// function BELOW it is later in the file, so it wins (last-in-the-text-wins). The
// 20-byte report, rumble, and capabilities all come from the S module unchanged.
//
// Why bother: some original-Xbox games read the controller's PID / XID subtype to
// tell which pad is plugged in. This presents as a genuine Duke for those.

import "xboxog_rawusb.qc"

string MODULE_ID      = "xboxog_duke";
string MODULE_NAME    = "Xbox Original Controller - The Duke (virtual USB / XID)";
string MODULE_VERSION = "1.0.0";

int    USB_PID        = 0x0202;   // The Duke
int    USB_BCD_DEVICE = 0x0100;
int    USB_EP0_SIZE   = 0x40;     // 64-byte control endpoint

void() declare_usb =
{
    // Same configuration as the Controller S, but the interrupt-IN endpoint is
    // 0x82 rather than 0x81 (the one config-descriptor byte that differs).
    usb_config(
        "09 02 20 00 01 01 00 80 32"   // configuration: 1 interface, bus-powered 100 mA
        "09 04 00 00 02 58 42 00 00"   // interface 0: class 58/42/00 (XID)
        "07 05 82 03 20 00 04"         // EP 0x82 IN,  interrupt, 32 B, 4 ms
        "07 05 02 03 20 00 04"         // EP 0x02 OUT, interrupt, 32 B, 4 ms
    );

    in_endpoint(0x82);    // pack() reports go out here (0x82, not the S's 0x81)
    out_endpoint(0x02);   // console rumble arrives here -> on_output()
};

bytes(int bmReqType, int bReq, int wValue, int wIndex, int wLength) on_control =
{
    // XID descriptor. Identical to the S except bSubType 0x01 = gamepad (Duke).
    if (bReq == 0x06 && wValue == 0x4200) {
        return hex("10 42 00 01 01 01 14 06 FF FF FF FF FF FF FF FF");
    }
    // Capabilities are the same as the Controller S (20-byte in / 6-byte out).
    if (bReq == 0x01 && wValue == 0x0100) {
        return hex("00 14 FF 00 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF");
    }
    if (bReq == 0x01 && wValue == 0x0200) {
        return hex("00 06 FF FF FF FF");
    }

    return hex("");   // unrecognised vendor request
};
