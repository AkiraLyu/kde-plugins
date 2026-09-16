#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later

"""Verify the real plasmoid's history settings across isolated host restarts.

Uses temporary Plasma configuration and a copied package with a fake launch
backend. No application is launched and no existing widget is modified.
"""

from __future__ import annotations

import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid


FIXTURE = r'''
    QtObject {
        id: historyFixture
        readonly property int count: 2
        function index(row, column) { return {row}; }
        function data(index, role) {
            switch (role) {
            case 0: return index.row ? "App Remembered" : "App Short";
            case 1: return "application-x-executable";
            case 257: return "Fixture";
            case 259: return "history-" + index.row + ".desktop";
            case 264: return false;
            case 265: return [];
            case 266: return "applications:history-" + index.row + ".desktop";
            }
            return undefined;
        }
        function trigger(row, action, argument) { return row >= 0 && row < count; }
    }

    function historyCheck(condition, message): void {
        if (!condition) { throw new Error(message); }
    }

    Timer {
        interval: 400
        running: true
        repeat: true
        property int step: 0
        onTriggered: {
            try {
                const phase = "@PHASE@";
                if (step++ === 0) {
                    layoutController.enableKRunnerSearch = false;
                    layoutController.sourceModel = historyFixture;
                    const saved = Plasmoid.configuration.launchHistoryData;
                    if (phase === "seed") {
                        root.historyCheck(saved === "", "initial history is not empty");
                        layoutController.launchApplication("history-1.desktop");
                        root.historyCheck(Plasmoid.configuration.launchHistoryData.includes("history-1.desktop"),
                            "launch did not reach the real configuration");
                    } else if (phase === "empty") {
                        root.historyCheck(saved === "", "cleared history returned after restart");
                        Plasmoid.configuration.rememberApplicationUsage = true;
                    } else {
                        root.historyCheck(saved.includes("history-1.desktop"), "history lost across restart");
                        root.historyCheck(layoutController.launchHistoryData === saved, "history not restored into controller");
                        if (phase === "disabled") {
                            Plasmoid.configuration.rememberApplicationUsage = false;
                        } else if (phase === "clear") {
                            root.historyCheck(!Plasmoid.configuration.rememberApplicationUsage, "disabled setting was lost");
                            Plasmoid.configuration.launchHistoryData = "";
                        }
                    }
                    layoutController.searchText = "app";
                    return;
                }
                const remembered = phase === "seed" || phase === "restore";
                root.historyCheck(layoutController.searchEntryAt(0).id === (remembered ? "history-1.desktop" : "history-0.desktop"),
                    "wrong search order after configuration change");
                root.historyCheck(layoutController.rootEntryAt(0).id === "history-0.desktop", "root layout changed");
                if (phase === "disabled") {
                    const saved = Plasmoid.configuration.launchHistoryData;
                    layoutController.launchApplication("history-0.desktop");
                    root.historyCheck(Plasmoid.configuration.launchHistoryData === saved, "learning continued while disabled");
                }
                Plasmoid.configuration.historySmokeResult = "@TOKEN@ PASS";
            } catch (error) {
                Plasmoid.configuration.historySmokeResult = "@TOKEN@ FAIL " + error;
            }
            stop();
        }
    }
'''


def run() -> None:
    repository = Path(__file__).resolve().parents[2]
    imports = repository / "build/qml"
    if not (imports / "org/kde/plasma/appgrid/core/qmldir").exists():
        raise RuntimeError("build the native App Grid modules first")
    host = shutil.which("plasmawindowed")
    if not host:
        raise RuntimeError("plasmawindowed is required")

    with tempfile.TemporaryDirectory(prefix="appgrid-history-smoke-") as temporary:
        directory = Path(temporary)
        plugin = "org.kde.plasma.appgrid.historysmoke"
        package = directory / "data/plasma/plasmoids" / plugin
        shutil.copytree(repository / "package", package)
        metadata = package / "metadata.json"
        info = json.loads(metadata.read_text())
        info["KPlugin"]["Id"] = plugin
        metadata.write_text(json.dumps(info))
        schema = package / "contents/config/main.xml"
        schema.write_text(schema.read_text().replace("</group>",
            '<entry name="historySmokeResult" type="String"><default></default></entry></group>'))
        main = package / "contents/ui/main.qml"
        original = main.read_text().rstrip()
        for name in ("config", "cache"):
            (directory / name).mkdir()
        environment = os.environ | {
            "XDG_CONFIG_HOME": str(directory / "config"),
            "XDG_CACHE_HOME": str(directory / "cache"),
            "XDG_DATA_HOME": str(directory / "data"),
            "QML_IMPORT_PATH": str(imports),
            "QML_DISABLE_DISK_CACHE": "1",
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QPA_PLATFORMTHEME": "",
            "QT_LOGGING_RULES": "kf.i18n.warning=false",
        }
        for phase in ("seed", "restore", "disabled", "clear", "empty"):
            token = uuid.uuid4().hex
            fixture = FIXTURE.replace("@PHASE@", phase).replace("@TOKEN@", token)
            main.write_text(original[:-1] + fixture + "}\n")
            with tempfile.TemporaryFile(mode="w+") as log:
                process = subprocess.Popen([host, plugin], env=environment,
                    stdout=log, stderr=subprocess.STDOUT)
                try:
                    deadline = time.monotonic() + 20
                    result = ""
                    while time.monotonic() < deadline and process.poll() is None:
                        config = directory / "config/plasmawindowedrc"
                        text = config.read_text() if config.exists() else ""
                        result = next((line for line in text.splitlines() if token in line), "")
                        if result:
                            break
                        time.sleep(0.05)
                    if f"{token} PASS" not in result:
                        log.seek(0)
                        raise RuntimeError(f"{phase}: {result or 'host did not persist a result'}\n{log.read()}")
                    print(f"PASS: {phase}", flush=True)
                finally:
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=3)


if __name__ == "__main__":
    run()
