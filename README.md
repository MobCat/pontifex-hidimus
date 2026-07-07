# Pontifex HIDimus
<img src="icon.png">

### The Great HID Bridge Builder

Pontifex Hidimus is a highly Configurable translator app or dongle for converting one HID into another HID.<br>
Convert raw ids and inputs from one device to another devices ids and inputs.<br>
(A HID is a Human Interface Device. A joystick, controller, keyboard, mouse. Anything that accepts human inputs from the real world and converts them to signals the computer can read)<br>
Think of it like a "software defined controller" you can make simple software scripts to convert any HID to another.<br>
We also just refer to it as `phidimus` for short hand a lot of the time.<br>

For eg.<br>
Convert a PS5 DualSence Controller into a Xbox 360 Wired Controller so you can use XInput natively<br>*(mapped to the real `xusb22.sys` driver included by default in windows)*<br>
Convert the IDs of your keyboard to another keyboard for games with specific keyboard functions (Logitech g15 and g19 screens and macros for eg.)<br>
Convert an Xbox controller into a Steal Battalion Controller, for fun.<br>
Bind an Xbox 360 controller with a chat pad to a generic keyboard and mouse.<br>
Map original xbox force feedback for racing wheels to ps5 DualSence adaptive triggers because why not.<br>
The limit should only be what you can define in a QC module, not what drivers are available for our system and a dozen custom once off config apps for the mappings.<br>
Pontifex HIDimus and its tools does all the hard work for you, you just have to make the modules and mappings. But lots of ini and qc files are provided as examples, or just to use out of the box if you don't want to program anything.

> [!WARNING]
> This project is not vegan.<br>
> AI was used heavily in the production of this code base.<br>
> And I don't feel as bad about it as I use to. The tools are there and cheap enough, ima use them. And I don't feel like I have to defend this decision but here we are.<br>
> It just feels weird to live in a world with power tools and then refuse to use them because you don't like how the tools are made.<br>
> If you are a vegan programmer, still like hand crafting with hand tools and do not agree with this then more power to you, but this warning and AI discloser is here and up front.<br>
> I did all the hard work, the AI is just faster and better at ingesting large amounts of code, and copy pasting stuff of stack overflow better and faster then I am.<br>
> A [references.md](docs/references.md) doc is available to see what code and projects we referenced and copied for this project.<br>
> Please also note, a lot of the docs where written by AI as well. I'm cleaning them up where I can, but some of them may still read weird. I would prefer complete docs written by AI then only a few hand crafted docs. Even if the AI docs are kinda shit to read sometimes.<br>
> AI was used heavily in this project, but 8 out of 10 times, I told the AI to put it there in the first place. It rarely ran off and did stuff on it's own, and if it did I rained it in the best I could.

# Why not just use Steam Input
Steam Input is a really grate system <i>however</i> it only works for games running under steam.<br>
Pontifex HIDimus aims to be a little more flexibal and not relient on 3rd partys as much as we can (because windows is poop)<br>
Say you want to use a controler on an old computer to play an old game that only supports joysticks, <br>well convert the controller you have into the joystick down to the HID IDs that game is looking for.<br>
Or that really old game doesnt have joystick support at all, well convert your controller into a fancy keyboard.<br>
Convert a random old usb controller like the SideWinder Game Pad Pro to an xbox 360 controller so it can be used on modern windows without special drivers.<br>
And vice versa, convert your xbox controller to a SideWinder Game Pad Pro to be used with old games or operating systems that natively support it.<br>
You want a special drawing pad for some CAD software but can't find it? Well make it with stuff you already have.<br>Pontifex Hidimus is not limited to just games or controllers. It converts a device down to HIDs and VIDs to another device.<br>
(Also if you're running a pirated steam game with a limited steam.dll that does not contain its own version of steam input.<br>
So you add your pirated game to Steam as a non steam game. Well Steam will overwrite your steam crack so the game will boot and then auto quit)

# Ethos and explainer ramble
The idea of Pontifex HIDimus is to convert one set of raw custom inputs to another set of raw custom inputs that your app or platform supports<br>
We try to be as low level as we can achieve in user space. For eg your computer already knows how to handle and read an xbox controller, we just have to pretend to be one with our own set of custom inputs.<br>
Converting at this level means we can convert anything to anything regardless of os drivers, support from software or the os itself.<br>
And the overhead is really low for this. We are just matching the input of one data struct to the output of another data struct. Takes under a ms to do.<br>
Sadly windows doesn't really let you plug random stuff into the kernel so we have to rely on existing drivers and spaces in the kernel to talk to, for eg.<br>
Hitching a ride on the back of `xusb22.sys` and just pretending to be an xbox controller. Down to the raw bytes.<br>
However these limitations are bypassed more or less when using the pi dongle. Both for just sorting modules and configs on the pi, but also using the pi as a raw dongle back to windows.<br>
Then we can do things like talk to the ps5 controller as a "real" ps5, not as a windows Bluetooth driver.<br><br>

We use the `ps5ds.qc` input module to read the raw inputs from a real ps5 controller, it gives some raw input like `0x28`. we use the phidimus engine to assign that to `BTN_CROSS`<br>
Then we use a config to tie `BTN_CROSS` to `XINPUT_GAMEPAD_A`<br>
Then we use the xbox output module to convert `XINPUT_GAMEPAD_A` from the phidimus engine to a raw output `0x1000`<br>
From the computers point of view, you just pressed `0x1000` not `0x28`.<br>
This is why Pontifex HIDimus converts devices with almost no lag. We are talking about under a millisecond so no perceivable lag. Or 3 cpu cycles if you prefer a real operation time.<br>
Get the raw input from the device, look it up in the pre-computed map, send the raw output back out.<br>
All the hard work of how to convert is done on config load, after that its just raw data == raw data.<br>
Your limitations come down to the devices you are converting, for eg the poling rate of Bluetooth. Or the poor og xbox running usb 1.1. if you hot plug a controller in 15ms then the xbox gets cranky.<br>
But Pontifex HIDimus is fully capable of doing said hot plug in 15ms or less if you want it to.

# Binding configs
Pontifex HIDimus uses a really simple ini config format to bind one QC module to another. Or many modules to many modules if you want.<br>
These configs are kept simple so anyone with a basic text editor can edit them easily and whenever they want with whatever they want.<br>
*More advanced tools like `phidimus-configurator` do exist, but you can still just use basic notepad if you want.*
```ini
[config]
id       = ps5ds_to_xbox360_raw
author   = MobCat
phidimus = 4.5.0
input    = ps5ds
output   = xbox360_usb
macro    = rapidfire
method   = raw_gadget
```
...
```ini
[xbox360_usb.buttons]
# Face buttons (PlayStation -> Xbox naming)
BTN_CROSS    = XINPUT_GAMEPAD_A
BTN_CIRCLE   = XINPUT_GAMEPAD_B
BTN_SQUARE   = XINPUT_GAMEPAD_X
BTN_TRIANGLE = XINPUT_GAMEPAD_Y

# Shoulders
BTN_L1 = XINPUT_GAMEPAD_LEFT_SHOULDER
BTN_R1 = XINPUT_GAMEPAD_RIGHT_SHOULDER

# Thumbstick clicks
BTN_L3 = XINPUT_GAMEPAD_LEFT_THUMB
BTN_R3 = XINPUT_GAMEPAD_RIGHT_THUMB
```

# Why QuakeC?
IDK I just thought it be fun.<br>
I feel like most projects if they want an in-between non compiled scripting language they just use LUA.<br>
Lua is fine, and modern lua could do everything we ask of it, but C is better at the task we are asking of it, reading and converting bytes into bytes.<br>
As we have our own QCVM build from the ground up in go, we own the whole stack. And can ship the whole stack ourselves.<br>
we only ship what we want and need, we don't need to ship a whole lua interpreter and vm that's not ours and we have no idea how it works.<br>
Both our ini passer and QCVM are not strictly vanilla, we have extended them with a few things like comments and usb functions respectively.<br>
But the idea is if you can wright and ini or know QuakeC then you should be right at home here.<br>
For QC, all docs relating to the things we have added are in [QC_USB_API_v4.md](docs/QC_USB_API_v4.md)<br>
If the top off my head, our ini passer is the same as normal, just expanded with comments.<br><br>

```c
void(bytes raw) parse =
{
    // BT: only decode report 0x31.
    if (IS_BT) {
        if (raw[0] != 0x31) { return; }
    }

    local int o = IS_BT;   // byte offset: 0 for USB, 1 for BT

    // Sticks and triggers
    set_axis("LEFT_STICK_X",  raw[1 + o]);
    set_axis("LEFT_STICK_Y",  raw[2 + o]);
    set_axis("RIGHT_STICK_X", raw[3 + o]);
    set_axis("RIGHT_STICK_Y", raw[4 + o]);
    set_axis("L2_ANALOG",     raw[5 + o]);
    set_axis("R2_ANALOG",     raw[6 + o]);

    // D-pad: low nibble of byte 8+o  (0=N 1=NE 2=E 3=SE 4=S 5=SW 6=W 7=NW 8=neutral)
    local int dpad = raw[8 + o] & 0x0F;
    set_btn("BTN_DPAD_UP",    dpad == 0 || dpad == 1 || dpad == 7);
    set_btn("BTN_DPAD_RIGHT", dpad == 1 || dpad == 2 || dpad == 3);
    set_btn("BTN_DPAD_DOWN",  dpad == 3 || dpad == 4 || dpad == 5);
    set_btn("BTN_DPAD_LEFT",  dpad == 5 || dpad == 6 || dpad == 7);

    // Face buttons: high nibble of byte 8+o
    set_btn("BTN_SQUARE",   raw[8 + o] & 0x10);
    set_btn("BTN_CROSS",    raw[8 + o] & 0x20);
    set_btn("BTN_CIRCLE",   raw[8 + o] & 0x40);
    set_btn("BTN_TRIANGLE", raw[8 + o] & 0x80);
```
...
```c
    // Battery: byte 53+o  (bits 3:0 = level 0-10, bit 4 = charging/plugged-in)
    local int batt = raw[53 + o];
    set_axis("BATTERY_LEVEL",   (batt & 0x0F) * 10);
    set_btn("BATTERY_CHARGING",  batt & 0x10);

    // Touchpad finger 1: bytes 33+o .. 36+o
    // Byte 33+o bit 7 = inactive (0=touching, 1=not touching)
    // X = 12 bits across bytes 34+o & 35+o low nibble
    // Y = 12 bits across bytes 35+o high nibble & 36+o
    local int t1_0 = raw[33 + o];
    local int t1_1 = raw[34 + o];
    local int t1_2 = raw[35 + o];
    local int touch1_x = t1_1 | ((t1_2 & 0x0F) << 8);
    local int touch1_y = (t1_2 >> 4) | (raw[36 + o] << 4);
    if (t1_0 & 0x80) {
        set_axis("TOUCH1_X", 960);
        set_axis("TOUCH1_Y", 540);
    } else {
        set_axis("TOUCH1_X", touch1_x);
        set_axis("TOUCH1_Y", touch1_y);
    }

    // Touchpad finger 2: bytes 37+o .. 40+o
    local int t2_0 = raw[37 + o];
    local int t2_1 = raw[38 + o];
    local int t2_2 = raw[39 + o];
    local int touch2_x = t2_1 | ((t2_2 & 0x0F) << 8);
    local int touch2_y = (t2_2 >> 4) | (raw[40 + o] << 4);
    if (t2_0 & 0x80) {
        set_axis("TOUCH2_X", 960);
        set_axis("TOUCH2_Y", 540);
    } else {
        set_axis("TOUCH2_X", touch2_x);
        set_axis("TOUCH2_Y", touch2_y);
    }
```

# How to get started
***TODO/placeholder:***
Simple pi setup is get a pi zero 2 w for the "lite" build of this project<br>
Get the waveshare OLED hat with buttons<br>
Get a micro sd card thats 1 to 32GB in size (really 1 or 2 GB is still more then you need)<br>
Flash/etch the pi image to your sd card<br>
Stick it in the pi, wait about 11 secs for the pi to boot and Pontifex HIDimus is ready to use.<br>
For simple BT to USB modes, you should plug the pi zero into the right most usb port. This is the only real data usb port the pi zero has. The other usb is just for power.<br>
For anything more advanced, like a USB to USB mode with full logging, you will need a full pi 3 or 4. But this branch is not built out yet.<br>
Most people just want to convert x to y. And the lite pi zero 2 build does that well.

# Hay you know x project already exists right. Why are you re-doing it.
Yes, check the [references.md](docs/references.md) I probs already read it and used some of it.<br>
I found a lot of controller adaptor projects both where single use, convert controller to one platform, and baked in all the controllers into the main code.<br>
Pontifex HIDimus is more flexible and configurable then this. If you want to make a new input, output, macro, or binding config, you should be able to just do that, you shouldn't need to setup and rebuild a whole code base for one change.<br>
Pontifex HIDimus ethos is that the input, output, macros, and binding configs are independent of each other. If a new controller comes out tomorrow like the steam controller,<br>
well you just wright a new `steamcontroller.qc` and it can be hooked into all existing output modules with simple inis in a few mins.
You don't need to re-program the whole input output pipe line for one new controller.<br>
You don't need to re-program a new rapid fire macro for every new controller.<br>
Just grab a new module and plug it into all the work that already exists with basic text edits.<br>
And TBH making things your self is fun. who cares if it already exists, are you having fun and learning something? Then good.

# Closing notes
If you would perfer what the AI has to say about this project, you can read that here [AI.README.md](AI.README.md)
