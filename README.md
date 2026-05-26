# Pontifex Hidimus
### The Great HID Bridge Builder

Pontifex Hidimus is a highly Configurable translator app for converting one HID into another HID.<br>
Convert raw ids and inputs from one device to another devices ids and inputs.<br>
(A HID is a Human Interface Device. A joystick, controller, keyboard, mouse. Anything that accepts human inputs from the real world and converts them to signals the computer can read)

For eg.<br>
Convert a PS5 DualSence Controller into a Xbox One Wired Controller so you can use XInput nativly.<br>
Convert the IDs of your keyboard to another keyboard for games with specific keyboard functions (logitech g15 and g19 screens and macros)<br>
Convert an Xbox controler into a Steal Battalion Controller, for fun.

# Why not just use Steamm Input
Steam Input is a really grate system <i>however</i> it only works for games running under steam.<br>
Pontifex Hidimus aims to be a little more flexibal and not relient on 3rd partys as much as we can (windows is poop)<br>
Say you want to use a controler on an old(ish, this app needs x64 to run) computer to play an old game that only supports joysticks, <br>well convert the controller you have into the joystick down to the HID IDs that game is looking for.<br>
Or that really old game doesnt have joystick support at all, well convert your controller into a fancy keyboard.<br>
You want a special drawing pad for some CAD software but can't find it? Well make it with stuff you already have. Pontifex Hidimus is not limited to just games or controllers.<br>

# Ethos
The idea of Pontifex Hidimus is to convert one set of raw custom inputs to another set of raw custom inputs that your app or platform supports<br>
We try to be as low level as we can achieve in user space. For eg your computer already knows how to handle and read an xbox controller, we just have to pretend to be one with our own set of custom inputs.<br>
Converting at this level means we can convert anything to anything regardless of os drivers, support from software or the os itself.<br>
And the overhead is really low for this. We are just matching the input of one data struct to the output of another data struct. Takes under a ms to do.<br>
Sadly windows doesn't really let you plug random stuff into the kernel so we have to rely on existing drivers and spaces in the kernel to talk to, witch i'm not a fan of but it is what it is.<br><br>

We use the ps5 input module to read the usb input from a real ps5 controller, it gives some raw input like 0x28. we use the phidimus sdk to assign that to BTN_CROSS<br>
Then we use a config to tie BTN_CROSS to XINPUT_GAMEPAD_A<br>
Then we use the xbox output module to convert XINPUT_GAMEPAD_A from the phidimus sdk to a raw output 0x1000<br>
From the computers point of view, you just pressed 0x1000 not 0x28.<br>
As low level as we can achieve in user space because windows doesn't really support the user just shoving random things into the kernel like this, so for windows we have to hitch a ride on established drivers like ViGEmBus.<br>
However the way Pontifex Hidimus is written if for some reason ViGEmBus goes away, you can just wright a new xbox output module for windows to support whatever replaced it, 
No need to edit the input modules as we already know how to listen to our custom devices, just the output changed.<br><br>

Pontifex Hidimus takes a modular approach to this device translation. We use a module to translate an input to a common language, we use a module to translate back from a common language to a custom output.<br>
Then we use a config to tie a custom input to a custom output by tying 2 common known input/output types together.<br>
`- { from: BTN_CROSS, to: XINPUT_GAMEPAD_A }`<br>
From the users point of view X button now equals A button, that's it. All the heavy lifting is done with the modules.<br>
Say you wanna convert a ps4 controller not a ps5 controller, well just use the ps4 input module in your config instead. No need to program anything new.<br>
Say you wanna convert something to some new random unique device, well just make an output module that translates that to our common language in phidimus sdk.<br>
