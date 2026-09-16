pragma ComponentBehavior: Bound

import QtQuick

import org.kde.taskmanager as TaskManager

QtObject {
    id: root

    property var applicationById: ({})
    // Replaceable for deterministic tests. The production source is KDE's
    // existing Wayland-aware task model, not a process/window-name heuristic.
    property bool useInternalTaskSource: true
    property var taskSource: null
    property var ownedTaskSource: null
    property var runningIds: ({})
    property int revision: 0
    property string keySignature: ""

    readonly property int appIdRole: TaskManager.AbstractTasksModel.AppId
    readonly property int launcherUrlRole:
        TaskManager.AbstractTasksModel.LauncherUrl
    readonly property int launcherUrlWithoutIconRole:
        TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon
    readonly property int isWindowRole:
        TaskManager.AbstractTasksModel.IsWindow
    readonly property int isStartupRole:
        TaskManager.AbstractTasksModel.IsStartup

    property Component internalTaskModelComponent: Component {
        TaskManager.TasksModel {
            groupMode: TaskManager.TasksModel.GroupDisabled
            sortMode: TaskManager.TasksModel.SortDisabled
        }
    }

    property Timer rebuildTimer: Timer {
        interval: 0
        repeat: false
        onTriggered: root.rebuild()
    }

    property Connections taskConnections: Connections {
        target: root.taskSource
        enabled: root.taskSource !== null
        ignoreUnknownSignals: true

        function onModelReset(): void {
            root.rebuildTimer.restart();
        }

        function onRowsInserted(): void {
            root.rebuildTimer.restart();
        }

        function onRowsRemoved(): void {
            root.rebuildTimer.restart();
        }

        function onDataChanged(): void {
            root.rebuildTimer.restart();
        }

        function onCountChanged(): void {
            root.rebuildTimer.restart();
        }
    }

    onApplicationByIdChanged: rebuildTimer.restart()
    onTaskSourceChanged: rebuildTimer.restart()
    onUseInternalTaskSourceChanged: _updateInternalTaskSource()
    Component.onCompleted: {
        _updateInternalTaskSource();
        rebuildTimer.restart();
    }

    function _updateInternalTaskSource(): void {
        if (useInternalTaskSource) {
            if (taskSource === null) {
                ownedTaskSource = internalTaskModelComponent.createObject(root);
                taskSource = ownedTaskSource;
            }
            return;
        }
        if (ownedTaskSource !== null) {
            if (taskSource === ownedTaskSource) {
                taskSource = null;
            }
            ownedTaskSource.destroy();
            ownedTaskSource = null;
        }
    }

    function _decode(value) {
        try {
            return decodeURIComponent(value);
        } catch (error) {
            return value;
        }
    }

    function _desktopIdFromUrl(value) {
        let text = String(value ?? "").trim();
        if (!text) {
            return "";
        }
        text = text.replace(/^applications:/, "");
        while (text.startsWith("/")) {
            text = text.slice(1);
        }
        const suffixOffset = text.search(/[?#]/);
        if (suffixOffset >= 0) {
            text = text.slice(0, suffixOffset);
        }
        text = _decode(text);
        if (text.startsWith("file://")) {
            text = text.slice("file://".length);
        }
        if (text.includes("/")) {
            text = text.slice(text.lastIndexOf("/") + 1);
        }
        return text;
    }

    function _installedId(candidate) {
        const value = String(candidate ?? "").trim();
        if (!value) {
            return "";
        }
        if (applicationById[value]) {
            return value;
        }
        const desktopId = value.endsWith(".desktop")
            ? value : `${value}.desktop`;
        return applicationById[desktopId] ? desktopId : "";
    }

    function rebuild(): void {
        const nextIds = Object.create(null);
        const model = taskSource;
        const count = model ? Number(model.count ?? 0) : 0;
        for (let row = 0; row < count; ++row) {
            const index = model.makeModelIndex
                ? model.makeModelIndex(row) : model.index(row, 0);
            if (!index) {
                continue;
            }
            const isWindow = Boolean(model.data(index, isWindowRole));
            const isStartup = Boolean(model.data(index, isStartupRole));
            if (!isWindow && !isStartup) {
                continue;
            }

            const launcherWithoutIcon = model.data(
                index, launcherUrlWithoutIconRole);
            const launcherId = _installedId(_desktopIdFromUrl(
                launcherWithoutIcon
                    ? launcherWithoutIcon
                    : model.data(index, launcherUrlRole)));
            const appId = launcherId || _installedId(
                model.data(index, appIdRole));
            if (appId) {
                nextIds[appId] = true;
            }
        }

        const signature = Object.keys(nextIds).sort().join("\u0000");
        if (signature === keySignature) {
            return;
        }
        keySignature = signature;
        runningIds = nextIds;
        revision += 1;
    }

    function isRunning(appId) {
        revision;
        return Boolean(runningIds[String(appId ?? "")]);
    }
}
