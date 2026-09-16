import QtQuick
import QtTest

import "../package/contents/ui"

TestCase {
    id: testCase

    name: "RunningApplications"

    readonly property var applicationIndex: ({
        "firefox.desktop": {id: "firefox.desktop"},
        "org.kde.dolphin.desktop": {id: "org.kde.dolphin.desktop"},
        "encoded app.desktop": {id: "encoded app.desktop"},
    })

    QtObject {
        id: fakeTasks

        property var records: []
        readonly property int count: records.length

        signal modelReset()
        signal dataChanged()

        function index(row, column) {
            return {row};
        }

        function makeModelIndex(row) {
            return index(row, 0);
        }

        function data(modelIndex, role) {
            const record = records[modelIndex.row];
            if (role === runningApplications.appIdRole) {
                return record.appId ?? "";
            }
            if (role === runningApplications.launcherUrlRole) {
                return record.launcherUrl ?? "";
            }
            if (role === runningApplications.launcherUrlWithoutIconRole) {
                return record.launcherUrlWithoutIcon ?? "";
            }
            if (role === runningApplications.isWindowRole) {
                return record.isWindow ?? false;
            }
            if (role === runningApplications.isStartupRole) {
                return record.isStartup ?? false;
            }
            return undefined;
        }
    }

    RunningApplications {
        id: runningApplications
        applicationById: testCase.applicationIndex
        useInternalTaskSource: false
        taskSource: fakeTasks
    }

    function init() {
        fakeTasks.records = [];
        fakeTasks.modelReset();
        tryCompare(runningApplications, "keySignature", "", 200);
    }

    function test_launcherUrlsAndAppIdsResolveToInstalledDesktopIds() {
        fakeTasks.records = [
            {
                isWindow: true,
                launcherUrlWithoutIcon: "applications:firefox.desktop?icon=firefox",
            },
            {
                isWindow: true,
                appId: "org.kde.dolphin",
            },
            {
                isStartup: true,
                launcherUrl: "applications:/encoded%20app.desktop",
            },
            {
                isWindow: false,
                appId: "ignored",
            },
        ];
        fakeTasks.modelReset();

        tryVerify(() => runningApplications.isRunning("firefox.desktop"), 200);
        verify(runningApplications.isRunning("org.kde.dolphin.desktop"));
        verify(runningApplications.isRunning("encoded app.desktop"));
        compare(runningApplications.isRunning("ignored.desktop"), false);
    }

    function test_removedWindowsClearTheRunningSet() {
        fakeTasks.records = [{isWindow: true, appId: "firefox"}];
        fakeTasks.modelReset();
        tryVerify(() => runningApplications.isRunning("firefox.desktop"), 200);

        fakeTasks.records = [];
        fakeTasks.modelReset();
        tryCompare(runningApplications, "keySignature", "", 200);
        compare(runningApplications.isRunning("firefox.desktop"), false);
    }

    function test_unchangedTaskUpdatesDoNotChurnRevision() {
        fakeTasks.records = [{isWindow: true, appId: "firefox"}];
        fakeTasks.modelReset();
        tryVerify(() => runningApplications.isRunning("firefox.desktop"), 200);
        const originalRevision = runningApplications.revision;

        fakeTasks.dataChanged();
        wait(0);
        compare(runningApplications.revision, originalRevision);
    }
}
