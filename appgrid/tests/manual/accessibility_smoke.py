#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Validate the visual harness accessibility tree through AT-SPI."""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass

try:
    import gi

    gi.require_version("Atspi", "2.0")
    from gi.repository import Atspi
except (ImportError, ValueError) as error:
    raise SystemExit(f"AT-SPI Python bindings are unavailable: {error}") from error


@dataclass(frozen=True)
class AccessibleNode:
    role: str
    name: str


def find_named(node: object, name: str) -> object | None:
    try:
        if (node.get_name() or "") == name:
            return node
        for index in range(node.get_child_count()):
            match = find_named(node.get_child_at_index(index), name)
            if match is not None:
                return match
    except Exception:
        return None
    return None


def wait_for_harness(timeout: float) -> object:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        harness = find_named(Atspi.get_desktop(0), "App Grid visual harness")
        if harness is not None:
            return harness
        time.sleep(0.1)
    raise RuntimeError("App Grid visual harness did not appear on AT-SPI")


def flatten(node: object) -> list[AccessibleNode]:
    result: list[AccessibleNode] = []

    def visit(current: object) -> None:
        try:
            result.append(
                AccessibleNode(current.get_role_name(), current.get_name() or "")
            )
            for index in range(current.get_child_count()):
                visit(current.get_child_at_index(index))
        except Exception as error:
            raise RuntimeError(f"could not traverse AT-SPI tree: {error}") from error

    visit(node)
    return result


def require(nodes: list[AccessibleNode], expected: set[AccessibleNode]) -> list[str]:
    available = set(nodes)
    return [
        f"missing {node.role!r} named {node.name!r}"
        for node in sorted(expected - available, key=lambda item: (item.role, item.name))
    ]


def forbid(nodes: list[AccessibleNode], forbidden_names: set[str]) -> list[str]:
    return [
        f"hidden control leaked as {node.role!r} named {node.name!r}"
        for node in nodes
        if node.name in forbidden_names
    ]


def validate(nodes: list[AccessibleNode], folder: bool) -> list[str]:
    common = {
        AccessibleNode("frame", "App Grid visual harness"),
        AccessibleNode("panel", "Applications"),
    }
    if folder:
        expected = common | {
            AccessibleNode("dialog", "Utilities"),
            AccessibleNode("text", "Folder name"),
            AccessibleNode("button", "Close folder"),
            AccessibleNode("button", "org.kde.dolphin"),
            AccessibleNode("button", "systemsettings"),
        }
        forbidden = {
            "Type to search",
            "Utilities",
            "firefox",
            "Page 1 of 2",
            "Page 2 of 2",
            "Next page",
            "Previous page",
            "Restore hidden applications",
        }
        errors = require(nodes, expected)
        errors.extend(
            f"background control leaked as {node.role!r} named {node.name!r}"
            for node in nodes
            if node.name in forbidden and node.role != "dialog"
        )
        return errors

    expected = common | {
        AccessibleNode("text", "Type to search"),
        AccessibleNode("button", "Utilities"),
        AccessibleNode("button", "firefox"),
        AccessibleNode("button", "Page 1 of 2"),
        AccessibleNode("button", "Page 2 of 2"),
        AccessibleNode("button", "Next page"),
    }
    forbidden = {
        "Clear search",
        "Previous page",
        "Close folder",
        "Folder name",
        "Application 38",
        "Restore hidden applications",
    }
    errors = require(nodes, expected)
    errors.extend(forbid(nodes, forbidden))
    visible_buttons = [node for node in nodes if node.role == "button"]
    if len(visible_buttons) != 27:
        errors.append(
            "expected 24 current-page app buttons, two page buttons, and "
            f"Next; found {len(visible_buttons)} buttons"
        )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", action="store_true")
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument(
        "--dump", action="store_true", help="print the observed role/name tree"
    )
    args = parser.parse_args()

    try:
        nodes = flatten(wait_for_harness(max(0.1, args.timeout)))
    except RuntimeError as error:
        parser.error(str(error))

    if args.dump:
        for node in nodes:
            print(f"{node.role}: {node.name}")

    errors = validate(nodes, args.folder)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    state = "folder modal" if args.folder else "application grid"
    print(f"AT-SPI smoke passed for {state} ({len(nodes)} accessible nodes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
