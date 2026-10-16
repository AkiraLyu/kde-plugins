#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Run the integration test in an isolated, headless KWin Wayland session."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def run_inside_session(kwin, test, *arguments):
    with tempfile.TemporaryFile(mode="w+") as log:
        compositor = subprocess.Popen(
            [kwin, "--virtual", "--width", "1600", "--height", "900",
             "--no-lockscreen", "--no-kactivities", "--socket", os.environ["WAYLAND_DISPLAY"]],
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        status = 1
        try:
            socket = Path(os.environ["XDG_RUNTIME_DIR"]) / os.environ["WAYLAND_DISPLAY"]
            deadline = time.monotonic() + 10
            while not socket.exists():
                if compositor.poll() is not None or time.monotonic() >= deadline:
                    raise RuntimeError("KWin did not start its Wayland display")
                time.sleep(0.05)
            status = subprocess.run([test, *arguments], timeout=60, check=False).returncode
        finally:
            if compositor.poll() is None:
                os.killpg(compositor.pid, signal.SIGTERM)
                try:
                    compositor.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(compositor.pid, signal.SIGKILL)
                    compositor.wait()
            if status:
                log.seek(0)
                print(log.read(), file=sys.stderr)
        return status


def main():
    if sys.argv[1] == "--inside-session":
        return run_inside_session(*sys.argv[2:])

    dbus, *arguments = sys.argv[1:]
    with tempfile.TemporaryDirectory(prefix="task-manager-smoke-") as temporary, tempfile.TemporaryFile(mode="w+") as log:
        environment = os.environ.copy()
        # Set isolation before starting D-Bus so activated services use it too.
        for variable, directory in (
            ("XDG_RUNTIME_DIR", "runtime"),
            ("XDG_CONFIG_HOME", "config"),
            ("XDG_DATA_HOME", "data"),
            ("XDG_CACHE_HOME", "cache"),
        ):
            path = Path(temporary) / directory
            path.mkdir(mode=0o700)
            environment[variable] = str(path)
        environment["WAYLAND_DISPLAY"] = "task-manager-smoke"
        environment["TASK_MANAGER_TEST_SESSION"] = "1"
        environment.pop("DISPLAY", None)
        environment.pop("SESSION_MANAGER", None)

        # Capture output in a file: activated services can outlive D-Bus and
        # would otherwise hold CTest's output pipe open after the test finishes.
        session = subprocess.Popen(
            [dbus, "--", sys.executable, __file__, "--inside-session", *arguments],
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            return session.wait(timeout=80)
        finally:
            try:
                os.killpg(session.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            log.seek(0)
            print(log.read(), end="")


if __name__ == "__main__":
    sys.exit(main())
