import QtQuick
import QtQuick.Window

import org.kde.plasma.private.kicker as Kicker

Window {
    id: root

    width: 1
    height: 1
    visible: true

    property Kicker.RootModel applicationRootModel: Kicker.RootModel {
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

        onRefreshed: root.inspectModel()
    }

    property Timer timeoutTimer: Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.error("Kicker application model did not refresh in time");
            Qt.exit(1);
        }
    }

    Component.onCompleted: applicationRootModel.refresh()

    function inspectModel(): void {
        let applications = null;
        for (let row = 0; row < applicationRootModel.count; ++row) {
            const candidate = applicationRootModel.modelForRow(row);
            if (candidate && candidate.description === "KICKER_ALL_MODEL") {
                applications = candidate;
                break;
            }
        }

        if (!applications) {
            console.error("Kicker did not expose its all-applications model");
            Qt.exit(1);
            return;
        }

        const seenIds = Object.create(null);
        let validIcons = 0;
        let validDescriptions = 0;
        let validUrls = 0;
        let actionRows = 0;
        for (let row = 0; row < applications.count; ++row) {
            const index = applications.index(row, 0);
            const id = String(applications.data(index, 259) ?? "");
            const title = String(applications.data(index, 0) ?? "");
            const icon = String(applications.data(index, 1) ?? "");
            if (!id || !title || seenIds[id]) {
                console.error(`Invalid or duplicate application at row ${row}: ${id}`);
                Qt.exit(1);
                return;
            }
            seenIds[id] = true;
            if (icon) {
                validIcons += 1;
            }
            if (String(applications.data(index, 257) ?? "")) {
                validDescriptions += 1;
            }
            if (String(applications.data(index, 266) ?? "")) {
                validUrls += 1;
            }
            if (Boolean(applications.data(index, 264))) {
                // Fetching the action-list role is the same lazy path used by
                // AppActionMenu; it must be convertible to a QML array.
                Array.from(applications.data(index, 265) ?? []);
                actionRows += 1;
            }
        }

        if (applications.count < 1 || validIcons < 1
                || validDescriptions < 1 || validUrls < 1
                || actionRows < 1) {
            console.error("Kicker returned incomplete application metadata");
            Qt.exit(1);
            return;
        }

        timeoutTimer.stop();
        console.info(`Kicker returned ${applications.count} unique applications `
            + `(${validIcons} icons, ${validDescriptions} descriptions, `
            + `${validUrls} URLs, ${actionRows} action lists)`);
        Qt.quit();
    }
}
