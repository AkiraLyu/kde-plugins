#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Test AppGridWindow output removal in an isolated two-output KWin."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import time


READY_PREFIX = "APPGRID_MULTI_OUTPUT_READY "
PASSED_PREFIX = "APPGRID_MULTI_OUTPUT_PASSED "


def require_program(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise RuntimeError(f"required program is unavailable: {name}")
    return path


def terminate(process: subprocess.Popen[str] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def wait_for_socket(path: Path, process: subprocess.Popen[str], timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        if process.poll() is not None:
            raise RuntimeError(f"nested KWin exited with status {process.returncode}")
        time.sleep(0.05)
    raise RuntimeError("nested KWin did not create its Wayland socket")


def read_until(
    process: subprocess.Popen[str], marker: str, timeout: float
) -> tuple[str, list[str]]:
    if process.stdout is None:
        raise RuntimeError("smoke process output is unavailable")
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    output: list[str] = []
    try:
        while time.monotonic() < deadline:
            events = selector.select(min(0.2, max(0.0, deadline - time.monotonic())))
            for key, _ in events:
                line = key.fileobj.readline()
                if line:
                    output.append(line.rstrip())
                    position = line.find(marker)
                    if position >= 0:
                        return line[position + len(marker) :].strip(), output
            if process.poll() is not None:
                remaining = process.stdout.read()
                output.extend(remaining.splitlines())
                details = "\n".join(output)
                raise RuntimeError(
                    f"QML smoke exited with status {process.returncode} before "
                    f"{marker}:\n{details}"
                )
    finally:
        selector.close()
    details = "\n".join(output)
    raise RuntimeError(f"timed out waiting for {marker}:\n{details}")


def run_inside(timeout: float) -> int:
    repository = Path(__file__).resolve().parents[2]
    qml_harness = repository / "tests/manual/MultiOutputSmoke.qml"
    effects_import = repository / "build/qml"
    if not (effects_import / "org/kde/plasma/appgrid/effects/qmldir").is_file():
        raise RuntimeError("build the native background-effect QML module first")
    kwin = require_program("kwin_wayland")
    qml = require_program("qml6")
    kscreen_doctor = require_program("kscreen-doctor")

    kwin_process: subprocess.Popen[str] | None = None
    qml_process: subprocess.Popen[str] | None = None
    with tempfile.TemporaryDirectory(prefix="appgrid-multi-output-") as temporary:
        temporary_path = Path(temporary)
        runtime = temporary_path / "runtime"
        runtime.mkdir(mode=0o700)
        for directory in ("config", "cache", "data"):
            (temporary_path / directory).mkdir()

        base_environment = os.environ.copy()
        base_environment.update(
            {
                "XDG_RUNTIME_DIR": str(runtime),
                "XDG_CONFIG_HOME": str(temporary_path / "config"),
                "XDG_CACHE_HOME": str(temporary_path / "cache"),
                "XDG_DATA_HOME": str(temporary_path / "data"),
            }
        )
        wayland_socket = "appgrid-multi-output"
        try:
            kwin_process = subprocess.Popen(
                [
                    kwin,
                    "--virtual",
                    "--output-count",
                    "2",
                    "--width",
                    "1280",
                    "--height",
                    "720",
                    "--scale",
                    "1",
                    "--no-lockscreen",
                    "--no-global-shortcuts",
                    "--socket",
                    wayland_socket,
                ],
                env=base_environment,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            wait_for_socket(runtime / wayland_socket, kwin_process, 5)

            client_environment = base_environment.copy()
            client_environment.update(
                {
                    "QT_QPA_PLATFORM": "wayland",
                    "WAYLAND_DISPLAY": wayland_socket,
                    "QT_LOGGING_RULES": "kf.i18n.warning=false",
                    "QT_FORCE_STDERR_LOGGING": "1",
                }
            )
            qml_process = subprocess.Popen(
                [
                    qml,
                    "-I",
                    str(effects_import),
                    "-I",
                    str(repository / "package/contents/ui"),
                    str(qml_harness),
                ],
                env=client_environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            target_screen, initial_output = read_until(
                qml_process, READY_PREFIX, timeout
            )
            doctor = subprocess.run(
                [kscreen_doctor, f"output.{target_screen}.disable"],
                env=client_environment,
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if doctor.returncode != 0:
                details = (doctor.stdout + doctor.stderr).strip()
                raise RuntimeError(
                    f"could not disable nested output {target_screen}: {details}"
                )

            _, final_output = read_until(qml_process, PASSED_PREFIX, timeout)
            status = qml_process.wait(timeout=3)
            if status != 0:
                raise RuntimeError(f"QML smoke exited with status {status}")
            markers = [
                line[line.find("APPGRID_MULTI_OUTPUT_") :]
                for line in initial_output + final_output
                if "APPGRID_MULTI_OUTPUT_" in line
            ]
            print("\n".join(markers))
            return 0
        finally:
            terminate(qml_process)
            terminate(kwin_process)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--inside-session", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()

    try:
        if args.inside_session:
            return run_inside(max(1.0, args.timeout))
        dbus_run_session = require_program("dbus-run-session")
        command = [
            dbus_run_session,
            "--",
            sys.executable,
            str(Path(__file__).resolve()),
            "--inside-session",
            "--timeout",
            str(args.timeout),
        ]
        return subprocess.run(
            command, stderr=subprocess.DEVNULL, check=False
        ).returncode
    except (RuntimeError, subprocess.SubprocessError) as error:
        if args.inside_session:
            print(f"multi-output smoke failed: {error}")
            return 2
        parser.error(str(error))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
