import QtQuick
import QtQuick.Window

import org.kde.plasma.private.kicker as Kicker

Window {
    id: root

    width: 1
    height: 1
    visible: true
    property bool started: false
    readonly property var runtimeArguments: Qt.application.arguments
    readonly property int separatorIndex: runtimeArguments.indexOf("--")
    readonly property string queryText: separatorIndex >= 0
        ? runtimeArguments.slice(separatorIndex + 1).join(" ") : "6 * 7"

    property Kicker.RunnerModel runnerModel: Kicker.RunnerModel {
        mergeResults: true
        runners: [
            "krunner_services",
            "krunner_systemsettings",
            "krunner_sessions",
            "krunner_powerdevil",
            "calculator",
            "unitconverter",
        ]

        onQueryFinished: {
            if (root.started) {
                root.finish();
            }
        }
    }

    property Timer timeoutTimer: Timer {
        interval: 5000
        onTriggered: {
            console.error("KRunner smoke test timed out");
            Qt.exit(2);
        }
    }

    function finish(): void {
        timeoutTimer.stop();
        if (runnerModel.count < 1) {
            console.error("KRunner did not expose a result model");
            Qt.exit(3);
            return;
        }

        const matches = runnerModel.modelForRow(0);
        console.info(`KRunner returned ${matches.count} matches for ${queryText}`);
        for (let row = 0; row < Math.min(matches.count, 5); ++row) {
            const index = matches.index(row, 0);
            console.info(`${String(matches.data(index, 0))} | `
                + `group=${String(matches.data(index, 258) ?? "")} | `
                + `favorite=${String(matches.data(index, 259) ?? "")}`);
        }
        Qt.exit(matches.count > 0 ? 0 : 4);
    }

    Component.onCompleted: {
        console.warn("Starting KRunner smoke test");
        timeoutTimer.start();
        started = true;
        Qt.callLater(() => runnerModel.query = queryText);
    }
}
