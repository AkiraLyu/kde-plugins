#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Inject a real KWin/libinput mouse-wheel or touchpad paging gesture."""

from __future__ import annotations

import argparse
import fcntl
import os
import struct
import subprocess
import time
from collections.abc import Iterable


EV_SYN = 0
EV_KEY = 1
EV_REL = 2
EV_ABS = 3
SYN_REPORT = 0

BTN_LEFT = 272
BTN_RIGHT = 273
BTN_MIDDLE = 274
BTN_TOOL_FINGER = 325
BTN_TOOL_QUINTTAP = 328
BTN_TOUCH = 330
BTN_TOOL_DOUBLETAP = 333
BTN_TOOL_TRIPLETAP = 334
BTN_TOOL_QUADTAP = 335

REL_X = 0
REL_Y = 1
REL_HWHEEL = 6
REL_WHEEL = 8

ABS_X = 0
ABS_Y = 1
ABS_MT_SLOT = 47
ABS_MT_POSITION_X = 53
ABS_MT_POSITION_Y = 54
ABS_MT_TOOL_TYPE = 55
ABS_MT_TRACKING_ID = 57

INPUT_PROP_POINTER = 0
INPUT_PROP_BUTTONPAD = 2
BUS_USB = 3

IOC_WRITE = 1
UINPUT_TYPE = "U"


def _ioc(direction: int, number: int, size: int) -> int:
    return (direction << 30) | (ord(UINPUT_TYPE) << 8) | number | (size << 16)


def _iow(number: int, size: int = 4) -> int:
    return _ioc(IOC_WRITE, number, size)


def _io(number: int) -> int:
    return _ioc(0, number, 0)


UI_DEV_CREATE = _io(1)
UI_DEV_DESTROY = _io(2)
UI_DEV_SETUP = lambda size: _iow(3, size)
UI_ABS_SETUP = lambda size: _iow(4, size)
UI_SET_EVBIT = _iow(100)
UI_SET_KEYBIT = _iow(101)
UI_SET_RELBIT = _iow(102)
UI_SET_PROPBIT = _iow(110)


class VirtualInput:
    def __init__(self, name: str, product: int) -> None:
        self.fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        self.name = name
        self.product = product
        self.created = False

    def ioctl_each(self, request: int, values: Iterable[int]) -> None:
        for value in values:
            fcntl.ioctl(self.fd, request, value)

    def setup(self) -> None:
        encoded_name = self.name.encode("utf-8")[:79]
        setup = struct.pack(
            "HHHH80sI", BUS_USB, 0x1209, self.product, 1, encoded_name, 0
        )
        fcntl.ioctl(self.fd, UI_DEV_SETUP(len(setup)), setup)
        fcntl.ioctl(self.fd, UI_DEV_CREATE)
        self.created = True

    def event(self, event_type: int, code: int, value: int) -> None:
        os.write(self.fd, struct.pack("llHHi", 0, 0, event_type, code, value))

    def sync(self) -> None:
        self.event(EV_SYN, SYN_REPORT, 0)

    def close(self) -> None:
        if self.created:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
            self.created = False
        os.close(self.fd)


def create_mouse() -> VirtualInput:
    device = VirtualInput("AppGrid Wayland Mouse Smoke", 0xA991)
    device.ioctl_each(UI_SET_EVBIT, (EV_KEY, EV_REL))
    device.ioctl_each(UI_SET_KEYBIT, (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE))
    device.ioctl_each(UI_SET_RELBIT, (REL_X, REL_Y, REL_HWHEEL, REL_WHEEL))
    fcntl.ioctl(device.fd, UI_SET_PROPBIT, INPUT_PROP_POINTER)
    device.setup()
    return device


def _setup_absolute_axis(
    device: VirtualInput, code: int, minimum: int, maximum: int, resolution: int
) -> None:
    setup = struct.pack(
        "H2xiiiiii", code, 0, minimum, maximum, 0, 0, resolution
    )
    fcntl.ioctl(device.fd, UI_ABS_SETUP(len(setup)), setup)


def create_touchpad() -> VirtualInput:
    device = VirtualInput("AppGrid Wayland Touchpad Smoke", 0xB001)
    device.ioctl_each(UI_SET_EVBIT, (EV_KEY, EV_ABS))
    device.ioctl_each(
        UI_SET_KEYBIT,
        (
            BTN_LEFT,
            BTN_TOOL_FINGER,
            BTN_TOOL_QUINTTAP,
            BTN_TOUCH,
            BTN_TOOL_DOUBLETAP,
            BTN_TOOL_TRIPLETAP,
            BTN_TOOL_QUADTAP,
        ),
    )
    device.ioctl_each(
        UI_SET_PROPBIT, (INPUT_PROP_POINTER, INPUT_PROP_BUTTONPAD)
    )
    for code, minimum, maximum, resolution in (
        (ABS_X, 0, 3684, 31),
        (ABS_Y, 0, 2176, 31),
        (ABS_MT_SLOT, 0, 4, 0),
        (ABS_MT_POSITION_X, 0, 3684, 31),
        (ABS_MT_POSITION_Y, 0, 2176, 31),
        (ABS_MT_TOOL_TYPE, 0, 2, 0),
        (ABS_MT_TRACKING_ID, 0, 65535, 0),
    ):
        _setup_absolute_axis(device, code, minimum, maximum, resolution)
    device.setup()
    return device


def inject_mouse(device: VirtualInput) -> None:
    # A negative evdev wheel tick is the forward/down direction used by the
    # launcher to reach its next page.
    device.event(EV_REL, REL_WHEEL, -1)
    device.sync()


def _touchpad_slot(
    device: VirtualInput, slot: int, tracking_id: int | None, x: int, y: int
) -> None:
    device.event(EV_ABS, ABS_MT_SLOT, slot)
    if tracking_id is not None:
        device.event(EV_ABS, ABS_MT_TRACKING_ID, tracking_id)
    device.event(EV_ABS, ABS_MT_POSITION_X, x)
    device.event(EV_ABS, ABS_MT_POSITION_Y, y)


def inject_touchpad(device: VirtualInput) -> None:
    # Two contacts moving down produce libinput POINTER_SCROLL_FINGER updates
    # in the launcher's forward direction with non-natural scrolling.
    _touchpad_slot(device, 0, 10, 1300, 600)
    _touchpad_slot(device, 1, 11, 2300, 600)
    device.event(EV_ABS, ABS_X, 1300)
    device.event(EV_ABS, ABS_Y, 600)
    device.event(EV_KEY, BTN_TOUCH, 1)
    device.event(EV_KEY, BTN_TOOL_DOUBLETAP, 1)
    device.sync()
    time.sleep(0.1)

    for step in range(1, 41):
        y = 600 + step * 20
        _touchpad_slot(device, 0, None, 1300, y)
        _touchpad_slot(device, 1, None, 2300, y)
        device.event(EV_ABS, ABS_X, 1300)
        device.event(EV_ABS, ABS_Y, y)
        device.sync()
        time.sleep(0.016)

    device.event(EV_ABS, ABS_MT_SLOT, 0)
    device.event(EV_ABS, ABS_MT_TRACKING_ID, -1)
    device.event(EV_ABS, ABS_MT_SLOT, 1)
    device.event(EV_ABS, ABS_MT_TRACKING_ID, -1)
    device.event(EV_KEY, BTN_TOUCH, 0)
    device.event(EV_KEY, BTN_TOOL_DOUBLETAP, 0)
    device.sync()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", choices=("mouse", "touchpad"))
    parser.add_argument(
        "--delay",
        type=float,
        default=10.0,
        help="seconds to wait for KWin to adopt the hot-plugged device",
    )
    args = parser.parse_args()

    device: VirtualInput | None = None
    try:
        device = create_mouse() if args.device == "mouse" else create_touchpad()
        subprocess.run(("udevadm", "settle"), check=False)
        print(f"Created {device.name}; injecting in {args.delay:g}s", flush=True)
        time.sleep(max(0.0, args.delay))
        if args.device == "mouse":
            inject_mouse(device)
        else:
            inject_touchpad(device)
        print(f"Injected {args.device} next-page input", flush=True)
        time.sleep(2)
        return 0
    except PermissionError as error:
        parser.error(f"cannot write /dev/uinput: {error}")
    finally:
        if device is not None:
            device.close()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
