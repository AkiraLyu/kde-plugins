pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: root

    anchors.fill: parent
    activationTogglesExpanded: false
    preferredRepresentation: compactRepresentation
    compactRepresentation: compactComponent
    fullRepresentation: compactComponent
    toolTipMainText: Plasmoid.title
    toolTipSubText: i18nc(
        "@info:tooltip", "Open the full-screen application grid")

    Plasmoid.icon: "view-app-grid-symbolic"

    AppGridStyle {
        id: appGridStyle
        darkMode: Plasmoid.configuration.forceDarkMode
        backgroundBlurEnabled: Plasmoid.configuration.enableBackgroundBlur
        useCustomBackgroundColor: Plasmoid.configuration.useCustomBackgroundColor
        customBackgroundColor: Plasmoid.configuration.backgroundColor
        backgroundOpacity: Plasmoid.configuration.backgroundOpacity
        requestedIconSize: Plasmoid.configuration.iconSize
        animationsEnabled: !Plasmoid.configuration.reduceAnimations
    }

    LayoutController {
        id: layoutController
        appletInterface: root
        defaultFolderName: i18nc("Default app-folder name", "Unnamed Folder")
        includeDescriptionsInSearch: Plasmoid.configuration.showDescriptionsInSearch
        enableKRunnerSearch: Plasmoid.configuration.enableKRunnerSearch
        rememberApplicationUsage: Plasmoid.configuration.rememberApplicationUsage
        // KWin only grants the private window-management protocol to the
        // trusted shell process. Standalone QML/plasmawindowed previews remain
        // useful launcher views, but cannot expose task state on Wayland.
        runningTrackingEnabled: Qt.application.name === "plasmashell"

        onPersistenceRequested: serialized => {
            if (Plasmoid.configuration.layoutData !== serialized) {
                Plasmoid.configuration.layoutData = serialized;
            }
        }
        onLaunchHistoryPersistenceRequested: serialized => {
            if (Plasmoid.configuration.launchHistoryData !== serialized) {
                Plasmoid.configuration.launchHistoryData = serialized;
            }
        }
        onHiddenApplicationsPersistRequested: ids => {
            const values = Array.from(ids ?? []);
            if (!root.sameStringList(
                    Plasmoid.configuration.hiddenApplications, values)) {
                Plasmoid.configuration.hiddenApplications = values;
            }
        }
        onRestoreHiddenApplicationsRequested: {
            Plasmoid.configuration.hiddenApplications = [];
            applicationRootModel.refresh();
        }
    }

    Kicker.RootModel {
        id: applicationRootModel

        autoPopulate: false
        appNameFormat: 0
        appletInterface: root
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

        onRefreshed: root.adoptAllApplicationsModel()
    }

    Component {
        id: appGridWindowComponent

        AppGridWindow {
            controller: layoutController
            style: appGridStyle
        }
    }

    Component {
        id: compactComponent

        CompactRepresentation {
            windowComponent: appGridWindowComponent
        }
    }

    Connections {
        target: Plasmoid.configuration

        function onLayoutDataChanged(): void {
            if (Plasmoid.configuration.layoutData !== layoutController.serializedLayout) {
                layoutController.load(Plasmoid.configuration.layoutData);
            }
        }

        function onLaunchHistoryDataChanged(): void {
            layoutController.launchHistoryData = Plasmoid.configuration.launchHistoryData;
        }

        function onHiddenApplicationsChanged(): void {
            const values = Array.from(
                Plasmoid.configuration.hiddenApplications ?? []);
            if (!root.sameStringList(
                    layoutController.hiddenApplications, values)) {
                layoutController.hiddenApplications = values;
            }
        }
    }

    function sameStringList(left, right): bool {
        const leftValues = Array.from(left ?? []);
        const rightValues = Array.from(right ?? []);
        if (leftValues.length !== rightValues.length) {
            return false;
        }
        for (let index = 0; index < leftValues.length; ++index) {
            if (String(leftValues[index]) !== String(rightValues[index])) {
                return false;
            }
        }
        return true;
    }

    function adoptAllApplicationsModel(): void {
        for (let row = 0; row < applicationRootModel.count; ++row) {
            const candidate = applicationRootModel.modelForRow(row);
            if (candidate && candidate.description === "KICKER_ALL_MODEL") {
                layoutController.serializedLayout = Plasmoid.configuration.layoutData;
                layoutController.sourceModel = candidate;
                return;
            }
        }
    }

    Component.onCompleted: {
        layoutController.serializedLayout = Plasmoid.configuration.layoutData;
        layoutController.launchHistoryData = Plasmoid.configuration.launchHistoryData;
        layoutController.hiddenApplications = Array.from(
            Plasmoid.configuration.hiddenApplications ?? []);
        applicationRootModel.refresh();
    }
}
