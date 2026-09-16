import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker

import "../../package/contents/ui"

QQC2.ApplicationWindow {
    id: window

    width: 1536
    height: 864
    visible: true
    color: "black"
    title: "App Grid visual harness"
    readonly property var harnessArguments: Qt.application.arguments
    readonly property bool showActionMenu: harnessArguments.includes("--action-menu")
    readonly property bool showFolder: harnessArguments.includes("--folder")
    readonly property bool showSearch: harnessArguments.includes("--search")
    readonly property bool rightToLeft: harnessArguments.includes("--rtl")
    readonly property bool lightMode: harnessArguments.includes("--light")
    readonly property bool highContrast: harnessArguments.includes("--high-contrast")
    readonly property bool showRunning: harnessArguments.includes("--running")
    readonly property bool showLaunchAnimation:
        harnessArguments.includes("--launch-animation")
    readonly property bool inputSmoke:
        harnessArguments.includes("--input-smoke")
    readonly property string launchCaptureArgument:
        harnessArguments.find(argument =>
            String(argument).startsWith("--capture-launch=")) ?? ""
    readonly property string launchCapturePath: launchCaptureArgument
        ? launchCaptureArgument.slice("--capture-launch=".length) : ""
    readonly property string captureArgument:
        harnessArguments.find(argument =>
            String(argument).startsWith("--capture=")) ?? ""
    readonly property string capturePath: captureArgument
        ? captureArgument.slice("--capture=".length) : ""
    readonly property string captureDelayArgument:
        harnessArguments.find(argument =>
            String(argument).startsWith("--capture-after=")) ?? ""
    readonly property int captureDelay: {
        const value = captureDelayArgument
            ? Number(captureDelayArgument.slice("--capture-after=".length))
            : 350;
        return isFinite(value) ? Math.max(0, Math.round(value)) : 350;
    }
    readonly property bool useRealApplications: harnessArguments.includes("--real")
    property bool realModelAdopted: false

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.textColor: highContrast ? "#ffffff" : palette.windowText
    Kirigami.Theme.disabledTextColor: highContrast
        ? "#ffffff" : palette.placeholderText
    Kirigami.Theme.highlightedTextColor: highContrast
        ? "#000000" : palette.highlightedText
    Kirigami.Theme.backgroundColor: highContrast
        ? "#000000" : palette.window
    Kirigami.Theme.highlightColor: highContrast
        ? "#ffff00" : palette.highlight
    Kirigami.Theme.focusColor: highContrast
        ? "#ffff00" : palette.highlight
    Kirigami.Theme.hoverColor: highContrast
        ? "#ffff00" : palette.highlight

    readonly property var fixtureIcons: [
        "systemsettings", "org.kde.dolphin", "firefox", "org.kde.konsole",
        "kate", "org.kde.discover", "applications-office", "applications-graphics",
        "applications-multimedia", "applications-development", "applications-games",
        "applications-education", "preferences-system-network", "accessories-calculator",
        "utilities-terminal", "utilities-file-archiver", "internet-web-browser",
        "mail-client", "camera-photo", "multimedia-video-player",
    ]

    QtObject {
        id: fakeModel

        property var records: []
        readonly property int count: records.length

        signal modelReset()

        function index(row, column) {
            return {row};
        }

        function data(modelIndex, role) {
            const record = records[modelIndex.row];
            switch (role) {
            case 0: return record.title;
            case 1: return record.icon;
            case 257: return record.description;
            case 259: return record.id;
            case 264: return record.actions !== undefined && record.actions.length > 0;
            case 265: return record.actions ?? [];
            case 266: return `applications:${record.id}`;
            default: return undefined;
            }
        }

        function trigger(row, actionId, argument) {
            return row >= 0 && row < count;
        }
    }

    Kicker.RootModel {
        id: realRootModel

        autoPopulate: false
        appNameFormat: 0
        flat: true
        sorted: true
        showSeparators: false
        showTopLevelItems: false
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showRecentFolders: false
        showPowerSession: false
        showRootSeparator: false
        highlightNewlyInstalledApps: false

        onRefreshed: window.adoptRealApplicationModel()
    }

    Timer {
        id: realModelTimeout
        interval: 5000
        onTriggered: {
            console.error("Real application model did not refresh in time");
            Qt.exit(1);
        }
    }

    Timer {
        id: runningFixtureTimer
        interval: 50
        onTriggered: {
            controller.runningApplications.rebuildTimer.stop();
            controller.runningApplications.runningIds = ({
                "fixture-2.desktop": true,
                "fixture-5.desktop": true,
            });
            controller.runningApplications.keySignature =
                "fixture-2.desktop\u0000fixture-5.desktop";
            controller.runningApplications.revision += 1;
        }
    }

    Timer {
        id: launchFixtureTimer
        interval: 900
        repeat: true
        onTriggered: {
            appGridView.grid.selectIndex(1);
            appGridView.grid.activateSelected();
            if (window.launchCapturePath && !launchCaptureTimer.running) {
                launchCaptureTimer.restart();
            }
        }
    }

    Timer {
        id: launchCaptureTimer
        interval: Math.max(1,
            Math.round(appGridStyle.appLaunchDuration / 2))
        onTriggered: appGridView.grabToImage(result => {
            if (!result.saveToFile(window.launchCapturePath)) {
                console.error(`Could not save ${window.launchCapturePath}`);
            } else {
                console.info(`Saved ${window.launchCapturePath}`);
            }
            launchFixtureTimer.stop();
        })
    }

    Timer {
        id: viewCaptureTimer

        interval: window.captureDelay
        onTriggered: appGridView.grabToImage(result => {
            if (!result.saveToFile(window.capturePath)) {
                console.error(`Could not save ${window.capturePath}`);
                Qt.exit(1);
            } else {
                console.info(`Saved ${window.capturePath}`);
                Qt.exit(0);
            }
        })
    }

    Timer {
        id: inputSmokeTimeout
        interval: 20000
        onTriggered: {
            console.error("Input smoke test did not reach the next page");
            Qt.exit(2);
        }
    }

    Connections {
        target: appGridView.grid
        function onWheelInputObserved(source, delta): void {
            if (window.inputSmoke) {
                console.info(`Input smoke observed ${source}: ${delta}`);
            }
        }
        function onCurrentPageChanged(): void {
            if (window.inputSmoke && appGridView.grid.currentPage === 1) {
                inputSmokeTimeout.stop();
                console.info("Input smoke test reached page 2");
                Qt.callLater(() => Qt.exit(0));
            }
        }
    }

    AppGridStyle {
        id: appGridStyle
        darkMode: !(window.lightMode || window.highContrast)
        requestedIconSize: 96
        systemTextColor: window.highContrast
            ? "#ffffff" : Kirigami.Theme.textColor
        systemDisabledTextColor: window.highContrast
            ? "#ffffff" : Kirigami.Theme.disabledTextColor
        systemBackgroundColor: window.highContrast
            ? "#000000" : Kirigami.Theme.backgroundColor
        systemHighlightColor: window.highContrast
            ? "#ffff00" : Kirigami.Theme.highlightColor
    }

    LayoutController {
        id: controller
        enableKRunnerSearch: false
        runningTrackingEnabled: false
        defaultFolderName: "Utilities"
    }

    AppGridView {
        id: appGridView
        anchors.fill: parent
        style: appGridStyle
        controller: controller
        layoutDirectionOverride: window.rightToLeft ? Qt.RightToLeft : -1
        onCloseRequested: window.close()
    }

    AppActionMenu {
        id: actionMenuHarness
        visualParent: appGridView
        controller: controller
        entry: {
            controller.revision;
            return controller.count > 1 ? controller.rootEntryAt(1) : null;
        }
        sourceMode: "root"
    }

    Component.onCompleted: {
        if (useRealApplications) {
            realModelTimeout.start();
            realRootModel.refresh();
            return;
        }
        populateFixtureModel();
    }

    function populateFixtureModel(): void {
        const applications = [];
        for (let index = 0; index < 38; ++index) {
            applications.push({
                id: `fixture-${index}.desktop`,
                title: index < 20 ? fixtureIcons[index].split("-").join(" ") : `Application ${index + 1}`,
                icon: fixtureIcons[index % fixtureIcons.length],
                description: `Fixture application ${index + 1}`,
                actions: index === 2 ? [
                    {text: "Open New Window", icon: "window-new", actionId: "new-window"},
                    {type: "separator"},
                    {text: "Application Details", icon: "applications-other", actionId: "details"},
                ] : [],
            });
        }
        fakeModel.records = applications;
        controller.sourceModel = fakeModel;
        controller.dropRootItem(0, 1, true);
        appGridView.reset();
        appGridView.playEntrance();
        applyRequestedState();
        if (capturePath) {
            viewCaptureTimer.start();
        }
        if (showRunning) {
            runningFixtureTimer.restart();
        }
        if (showLaunchAnimation) {
            launchFixtureTimer.start();
        }
        if (inputSmoke) {
            inputSmokeTimeout.start();
        }
    }

    function applyRequestedState(): void {
        if (showFolder) {
            const firstEntry = controller.rootEntryAt(0);
            if (!firstEntry || firstEntry.type !== "folder") {
                controller.dropRootItem(0, 1, true);
            }
            Qt.callLater(() => {
                appGridView.grid.selectIndex(0);
                appGridView.grid.activateSelected();
            });
        } else if (showSearch) {
            appGridView.searchText = useRealApplications
                ? "firefox" : "application 3";
        } else if (showActionMenu) {
            Qt.callLater(() => actionMenuHarness.open(
                Math.round(window.width / 2), Math.round(window.height / 2)));
        }
    }

    function adoptRealApplicationModel(): void {
        for (let row = 0; row < realRootModel.count; ++row) {
            const candidate = realRootModel.modelForRow(row);
            if (candidate && candidate.description === "KICKER_ALL_MODEL") {
                realModelTimeout.stop();
                if (realModelAdopted) {
                    return;
                }
                realModelAdopted = true;
                controller.sourceModel = candidate;
                appGridView.reset();
                appGridView.playEntrance();
                console.info(`Showing ${controller.count} real applications`);
                applyRequestedState();
                if (capturePath) {
                    viewCaptureTimer.start();
                }
                return;
            }
        }
        console.error("Kicker did not expose its all-applications model");
        Qt.exit(1);
    }
}
