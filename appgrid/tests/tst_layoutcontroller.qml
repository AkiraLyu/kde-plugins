import QtQuick
import QtTest

import "../package/contents/ui"

TestCase {
    id: testCase

    name: "LayoutController"

    readonly property var baseApplications: [
        {id: "alpha.desktop", title: "Alpha", icon: "applications-graphics", description: "Drawing", url: "applications:alpha.desktop"},
        {id: "beta.desktop", title: "Beta", icon: "applications-system", description: "System utility", url: "applications:beta.desktop"},
        {id: "gamma.desktop", title: "Gamma", icon: "applications-office", description: "Office editor", url: "applications:gamma.desktop"},
        {id: "delta.desktop", title: "Delta", icon: "applications-multimedia", description: "Media player", url: "applications:delta.desktop"},
    ]

    QtObject {
        id: fakeModel

        property var records: testCase.baseApplications.slice()
        readonly property int count: records.length
        property int lastTriggeredRow: -1
        property string lastActionId: ""
        property var lastActionArgument: undefined
        property bool triggerResult: true

        signal modelReset()
        signal rowsInserted()
        signal rowsRemoved()
        signal rowsMoved()
        signal dataChanged()
        signal layoutChanged()

        function index(row, column) {
            return {row};
        }

        function data(modelIndex, role) {
            const record = records[modelIndex.row];
            switch (role) {
            case 0:
                return record.title;
            case 1:
                return record.icon;
            case 257:
                return record.description;
            case 259:
                return record.id;
            case 264:
                return record.actions !== undefined && record.actions.length > 0;
            case 265:
                return record.actions ?? [];
            case 266:
                return record.url;
            default:
                return undefined;
            }
        }

        function trigger(row, actionId, argument) {
            lastTriggeredRow = row;
            lastActionId = actionId;
            lastActionArgument = argument;
            return triggerResult && row >= 0 && row < count;
        }
    }

    LayoutController {
        id: controller
        runningTrackingEnabled: false
        enableKRunnerSearch: false
        defaultFolderName: "Folder"
    }

    SignalSpy {
        id: launchSpy
        target: controller
        signalName: "applicationLaunched"
    }

    SignalSpy {
        id: interactionSpy
        target: controller
        signalName: "interactionConcluded"
    }

    SignalSpy {
        id: restoreHiddenSpy
        target: controller
        signalName: "restoreHiddenApplicationsRequested"
    }

    SignalSpy {
        id: hiddenPersistSpy
        target: controller
        signalName: "hiddenApplicationsPersistRequested"
    }

    SignalSpy {
        id: folderRemovedSpy
        target: controller
        signalName: "folderRemoved"
    }

    SignalSpy {
        id: historyPersistSpy
        target: controller
        signalName: "launchHistoryPersistenceRequested"
    }

    function init() {
        launchSpy.clear();
        interactionSpy.clear();
        restoreHiddenSpy.clear();
        hiddenPersistSpy.clear();
        folderRemovedSpy.clear();
        fakeModel.lastTriggeredRow = -1;
        fakeModel.lastActionId = "";
        fakeModel.lastActionArgument = undefined;
        fakeModel.triggerResult = true;
        fakeModel.records = baseApplications.slice();
        controller.sourceModel = null;
        controller.serializedLayout = "";
        controller.searchText = "";
        controller.launchHistoryData = "";
        controller.rememberApplicationUsage = true;
        historyPersistSpy.clear();
        controller.hiddenApplications = [];
        controller.sourceModel = fakeModel;
        compare(controller.count, 4);
        folderRemovedSpy.clear();
    }

    function folderAt(row) {
        const entry = controller.rootEntryAt(row);
        verify(entry !== null);
        compare(entry.type, "folder");
        return entry;
    }

    function createFirstFolder() {
        controller.dropRootItem(0, 1, true);
        compare(controller.count, 3);
        return folderAt(0);
    }

    function test_initialSynchronizationUsesStableIds() {
        compare(controller.rootEntryAt(0).id, "alpha.desktop");
        compare(controller.rootEntryAt(3).id, "delta.desktop");
    }

    function test_rootReorder() {
        controller.moveRootItem(0, 3);
        compare(controller.rootEntryAt(0).id, "beta.desktop");
        compare(controller.rootEntryAt(3).id, "alpha.desktop");
    }

    function test_dropAppOnAppCreatesFolder() {
        const folder = createFirstFolder();
        compare(folder.apps.join(","), "beta.desktop,alpha.desktop");
        compare(controller.countFor("folder", folder.id), 2);
    }

    function test_dropAppOnFolderAddsMember() {
        const folder = createFirstFolder();
        controller.dropRootItem(1, 0, true);
        compare(controller.count, 2);
        compare(controller.rootEntryAt(0).apps.join(","),
                "beta.desktop,alpha.desktop,gamma.desktop");
        compare(controller.countFor("folder", folder.id), 3);
    }

    function test_dropEarlierAppOnLaterFolderUsesShiftedRow() {
        controller.load(JSON.stringify({
            version: 1,
            items: [
                {type: "app", id: "alpha.desktop"},
                {
                    type: "folder",
                    id: "later-folder",
                    name: "Later",
                    apps: ["beta.desktop", "gamma.desktop"],
                },
                {type: "app", id: "delta.desktop"},
            ],
        }));

        controller.dropRootItem(0, 1, true);
        compare(controller.count, 2);
        compare(controller.rootEntryAt(0).id, "later-folder");
        compare(controller.rootEntryAt(0).apps.join(","),
            "beta.desktop,gamma.desktop,alpha.desktop");
        compare(controller.rootEntryAt(1).id, "delta.desktop");
    }

    function test_folderRenameReorderAndUnpack() {
        const folder = createFirstFolder();
        controller.renameFolder(folder.id, "My Tools");
        compare(controller.folderName(folder.id), "My Tools");

        controller.reorderFolder(folder.id, 0, 1);
        compare(controller.rootEntryAt(0).apps.join(","),
                "alpha.desktop,beta.desktop");

        controller.unpackFolder(folder.id);
        compare(controller.count, 4);
        compare(controller.rootEntryAt(0).id, "alpha.desktop");
        compare(controller.rootEntryAt(1).id, "beta.desktop");
    }

    function test_moveOutKeepsFolderAndReturnsAppToRoot() {
        const folder = createFirstFolder();
        controller.removeFromFolder(folder.id, "beta.desktop", 1);
        compare(controller.count, 4);
        compare(controller.folderCount(folder.id), 1);
        compare(controller.rootEntryAt(1).id, "beta.desktop");
    }

    function test_moveLastMemberReplacesFolderInPlace() {
        const stored = JSON.stringify({
            version: 1,
            items: [
                {type: "folder", id: "single", name: "Single", apps: ["alpha.desktop"]},
                {type: "app", id: "beta.desktop"},
                {type: "app", id: "gamma.desktop"},
                {type: "app", id: "delta.desktop"},
            ],
        });
        controller.load(stored);
        compare(controller.folderCount("single"), 1);

        controller.removeFromFolder("single", "alpha.desktop", -1);
        compare(controller.count, 4);
        compare(controller.rootEntryAt(0).id, "alpha.desktop");
        compare(controller.rootEntryAt(1).id, "beta.desktop");
    }

    function test_launchDelegatesToKickerSourceRow() {
        controller.activate("root", 2, "");
        compare(fakeModel.lastTriggeredRow, 2);
        compare(fakeModel.lastActionId, "");
        compare(launchSpy.count, 1);
        compare(launchSpy.signalArguments[0][0], "gamma.desktop");
    }

    function test_sourceRowChangesAreObserved() {
        fakeModel.records = [
            baseApplications[1],
            baseApplications[0],
            baseApplications[2],
            baseApplications[3],
        ];
        fakeModel.rowsMoved();

        // Persisted grid order remains stable, but activation must use the
        // source model's new row for the same desktop ID.
        compare(controller.rootEntryAt(0).id, "alpha.desktop");
        controller.activate("root", 0, "");
        compare(fakeModel.lastTriggeredRow, 1);

        fakeModel.layoutChanged();
        compare(controller.rootEntryAt(0).id, "alpha.desktop");
    }

    function test_failedLaunchDoesNotCloseTheGrid() {
        fakeModel.triggerResult = false;
        controller.activate("root", 0, "");
        compare(fakeModel.lastTriggeredRow, 0);
        compare(launchSpy.count, 0);
        compare(controller.launchHistoryData, "");
    }

    function test_launchHistoryCoversRootFolderAndSearchWithoutChangingLayout() {
        const folder = createFirstFolder();
        const layout = controller.serializedLayout;
        const revision = controller.revision;
        controller.launchApplication("gamma.desktop");
        controller.activate("folder", 0, folder.id);
        controller.searchText = "alpha";
        tryCompare(controller, "searchCount", 1, 500);
        controller.activate("search", 0, "");

        const history = JSON.parse(controller.launchHistoryData).apps;
        compare(history.map(app => app.id).sort().join(","), "alpha.desktop,beta.desktop,gamma.desktop");
        verify(history.every(app => app.weight === 1));
        compare(controller.serializedLayout, layout);
        compare(controller.revision, revision);
        compare(historyPersistSpy.count, 3);
        compare(historyPersistSpy.signalArguments[2][0], controller.launchHistoryData);

        controller.rememberApplicationUsage = false;
        const saved = controller.launchHistoryData;
        controller.launchApplication("delta.desktop");
        compare(controller.launchHistoryData, saved);
        controller.launchHistoryData = "";
        compare(controller.searchController.historyCount, 0);
    }

    function test_onlyLaunchActionsContributeToHistory() {
        for (const action of ["editApplication", "addToDesktop", "_kicker_appstream", "forgetRecentDocuments"]) {
            controller.triggerAction("alpha.desktop", action, "private document path");
        }
        compare(controller.launchHistoryData, "");
        controller.triggerAction("alpha.desktop", "_kicker_jumpListAction", "new-window");
        controller.triggerAction("alpha.desktop", "_kicker_recentDocument", "private document path");
        const saved = controller.launchHistoryData;
        compare(JSON.parse(saved).apps[0].weight, 2);
        verify(!saved.includes("private document path"));
        fakeModel.triggerResult = false;
        controller.triggerAction("alpha.desktop", "_kicker_jumpListAction", "new-window");
        compare(controller.launchHistoryData, saved);
    }

    function test_rememberedOrderSurvivesReorderMergeAndModelRefresh() {
        controller.launchApplication("gamma.desktop");
        const saved = controller.launchHistoryData;
        createFirstFolder();
        controller.moveRootItem(1, 2);
        fakeModel.records = baseApplications.slice().reverse();
        fakeModel.modelReset();
        controller.searchText = "a";
        tryCompare(controller, "searchCount", 4, 500);
        compare(controller.searchEntryAt(0).id, "alpha.desktop");
        compare(controller.searchEntryAt(1).id, "gamma.desktop");
        compare(controller.launchHistoryData, saved);
        controller.activate("search", 1, "");
        compare(fakeModel.lastTriggeredRow, 1);
    }

    function test_kdeActionsAreLoadedOnDemandAndTriggered() {
        const actionArgument = {desktop: 2};
        fakeModel.records = [
            Object.assign({}, baseApplications[0], {
                actions: [{
                    text: "Open New Window",
                    icon: "window-new",
                    actionId: "open-new-window",
                    actionArgument,
                }, {
                    type: "separator",
                }, {
                    text: "Hide Application",
                    actionId: "hideApplication",
                }],
            }),
            baseApplications[1],
        ];
        controller.synchronize();

        const actions = controller.actionsFor("alpha.desktop");
        compare(actions.length, 1);
        compare(actions[0].actionId, "open-new-window");

        controller.triggerAction(
            "alpha.desktop", actions[0].actionId, actions[0].actionArgument);
        compare(fakeModel.lastTriggeredRow, 0);
        compare(fakeModel.lastActionId, "open-new-window");
        compare(fakeModel.lastActionArgument.desktop, 2);
        compare(interactionSpy.count, 1);
    }

    function test_restoreHiddenApplicationsIsExplicit() {
        controller.hiddenApplications = ["alpha.desktop"];
        compare(controller.hiddenApplicationCount, 1);
        controller.restoreHiddenApplications();
        compare(restoreHiddenSpy.count, 1);

        controller.hiddenApplications = [];
        controller.restoreHiddenApplications();
        compare(restoreHiddenSpy.count, 1);
    }

    function test_hideApplicationFiltersRootFolderAndSearch() {
        const folder = createFirstFolder();
        controller.searchText = "delta";
        tryCompare(controller, "searchCount", 1, 500);

        controller.hideApplication("alpha.desktop");
        compare(controller.hiddenApplicationCount, 1);
        // alpha lived inside the folder; beta remains.
        compare(controller.folderCount(folder.id), 1);
        controller.hideApplication("delta.desktop");
        compare(controller.count, 2);
        tryCompare(controller, "searchCount", 0, 500);

        // Hiding an unknown or already-hidden id must not churn persistence.
        const persisted = hiddenPersistSpy.signalArguments[hiddenPersistSpy.count - 1][0];
        compare(persisted.join(","), "alpha.desktop,delta.desktop");

        const spyCount = hiddenPersistSpy.count;
        controller.hideApplication("delta.desktop");
        verify(hiddenPersistSpy.count === spyCount);

        // Restoring re-introduces both apps in source order at the end.
        controller.hiddenApplications = [];
        compare(controller.count, 4);
        compare(controller.rootEntryAt(0).type, "folder");
        compare(controller.rootEntryAt(1).id, "gamma.desktop");
        compare(controller.rootEntryAt(2).id, "alpha.desktop");
        compare(controller.rootEntryAt(3).id, "delta.desktop");
    }

    function test_reconcileNotifiesWhenAnOpenFolderDisappears() {
        controller.load(JSON.stringify({
            version: 1,
            items: [{
                type: "folder",
                id: "single",
                name: "Single",
                apps: ["alpha.desktop"],
            }],
        }));
        compare(controller.folderCount("single"), 1);

        controller.hideApplication("alpha.desktop");
        compare(controller.folderCount("single"), 0);
        compare(folderRemovedSpy.count, 1);
        compare(folderRemovedSpy.signalArguments[0][0], "single");
    }

    function test_invalidAndDuplicateSourceEntriesAreFiltered() {
        fakeModel.records = [
            {id: "", title: "Invalid", icon: "unknown", description: "", url: ""},
            {id: "nameless.desktop", title: "", icon: "unknown", description: "", url: ""},
            baseApplications[0],
            {id: "alpha.desktop", title: "Duplicate", icon: "unknown", description: "", url: ""},
            baseApplications[1],
        ];
        controller.synchronize();

        compare(controller.count, 2);
        compare(controller.rootEntryAt(0).title, "Alpha");
        controller.activate("root", 0, "");
        compare(fakeModel.lastTriggeredRow, 2);

        controller.searchText = "alpha";
        tryCompare(controller, "searchCount", 1, 500);
        compare(controller.searchEntryAt(0).title, "Alpha");
    }

    function test_searchUsesAllAppsIncludingFolderMembers() {
        createFirstFolder();
        controller.searchText = "beta utility";
        tryCompare(controller, "searchCount", 1, 500);
        compare(controller.searchEntryAt(0).id, "beta.desktop");
    }

    function test_applicationChurnReconcilesLayout() {
        const folder = createFirstFolder();
        controller.serializedLayout = controller._serializeCurrentLayout();
        fakeModel.records = [
            baseApplications[0],
            baseApplications[2],
            baseApplications[3],
            {id: "epsilon.desktop", title: "Epsilon", icon: "applications-other", description: "New", url: "applications:epsilon.desktop"},
        ];
        controller.synchronize();

        compare(controller.folderCount(folder.id), 1);
        compare(controller.rootEntryAt(controller.count - 1).id, "epsilon.desktop");
        verify(controller._serializeCurrentLayout().indexOf("beta.desktop") < 0);
    }
}
