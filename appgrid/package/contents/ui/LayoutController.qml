pragma ComponentBehavior: Bound

import QtQuick

import "../code/LayoutStore.js" as LayoutStore

QtObject {
    id: root

    property var sourceModel: null
    property string serializedLayout: ""
    property string defaultFolderName: "Unnamed Folder"
    property bool includeDescriptionsInSearch: true
    property var hiddenApplications: []
    property var appletInterface: null
    property bool enableKRunnerSearch: true
    property bool rememberApplicationUsage: true
    property alias launchHistoryData: applicationSearch.historyData
    property bool runningTrackingEnabled: true
    property var searchRunners: [
        "krunner_services",
        "krunner_systemsettings",
        "krunner_sessions",
        "krunner_powerdevil",
        "calculator",
        "unitconverter",
    ]

    readonly property int count: rootCount
    readonly property int searchCount: searchController.count
    readonly property bool searchQuerying: searchController.querying
    readonly property int searchRevision: searchController.revision
    readonly property int hiddenApplicationCount: hiddenApplications
        ? hiddenApplications.length : 0
    readonly property int runningRevision: runningApplications.revision
    property string searchText: ""
    property var applications: []
    property int revision: 0

    // Immutable records are shared by the layout, folders and visible slots.
    // Publish one array per transaction; never round-trip the entire catalog
    // through ListModel roles and JSON when a single icon moves.
    property var layoutState: ({rows: [], folderCounts: {}, folderRows: {}, rootRowsById: {}})
    readonly property int rootCount: layoutState.rows.length
    readonly property var folderCounts: layoutState.folderCounts
    readonly property var folderRows: layoutState.folderRows
    readonly property var rootRowsById: layoutState.rootRowsById
    readonly property var layoutRows: layoutState.rows
    property var applicationById: ({})

    signal persistenceRequested(string serialized)
    signal hiddenApplicationsPersistRequested(var ids)
    signal applicationLaunched(string appId)
    signal launchHistoryPersistenceRequested(string serialized)
    signal interactionConcluded()
    signal folderOpenRequested(string folderId)
    signal folderRemoved(string folderId)
    signal restoreHiddenApplicationsRequested()

    // QAbstractItemModel roles exposed by Plasma's Kicker AbstractModel.
    readonly property int displayRole: 0
    readonly property int decorationRole: 1
    readonly property int descriptionRole: 257
    readonly property int favoriteIdRole: 259
    readonly property int hasActionListRole: 264
    readonly property int actionListRole: 265
    readonly property int urlRole: 266

    property SearchController searchController: SearchController {
        id: applicationSearch
        applications: root.applications
        applicationById: root.applicationById
        appletInterface: root.appletInterface
        query: root.searchText
        includeDescriptions: root.includeDescriptionsInSearch
        runnerSearchEnabled: root.enableKRunnerSearch
        historyEnabled: root.rememberApplicationUsage
        runners: root.searchRunners

        onQueryReplacementRequested: query => root.searchText = query
        onHistoryPersistenceRequested: serialized => root.launchHistoryPersistenceRequested(serialized)
    }

    property RunningApplications runningApplications: RunningApplications {
        applicationById: root.applicationById
        useInternalTaskSource: root.runningTrackingEnabled
    }

    property Timer persistenceTimer: Timer {
        interval: 120
        repeat: false
        onTriggered: {
            root.persistenceRequested(root.serializedLayout);
        }
    }

    property Connections sourceConnections: Connections {
        target: root.sourceModel
        enabled: root.sourceModel !== null
        ignoreUnknownSignals: true

        function onModelReset(): void {
            root.synchronize();
        }

        function onRowsInserted(): void {
            root.synchronize();
        }

        function onRowsRemoved(): void {
            root.synchronize();
        }

        function onRowsMoved(): void {
            root.synchronize();
        }

        function onDataChanged(): void {
            root.synchronize();
        }

        function onLayoutChanged(): void {
            root.synchronize();
        }
    }

    onSourceModelChanged: synchronize()

    onHiddenApplicationsChanged: {
        synchronize();
        hiddenApplicationsPersistRequested(
            hiddenApplications ? hiddenApplications.slice() : []);
    }

    function load(serialized): void {
        const value = String(serialized ?? "");
        if (value === serializedLayout && rootCount > 0) {
            return;
        }
        serializedLayout = value;
        synchronize();
    }

    function _readSourceApplications() {
        const records = [];
        const seenIds = Object.create(null);
        if (!sourceModel) {
            return records;
        }

        const hiddenIds = Object.create(null);
        for (const hiddenId of hiddenApplications ?? []) {
            hiddenIds[String(hiddenId)] = true;
        }
        const rows = Number(sourceModel.count ?? 0);
        for (let row = 0; row < rows; ++row) {
            const modelIndex = sourceModel.index(row, 0);
            const id = String(
                sourceModel.data(modelIndex, favoriteIdRole) ?? "").trim();
            const title = String(
                sourceModel.data(modelIndex, displayRole) ?? "").trim();
            if (!id || !title || hiddenIds[id] || seenIds[id]) {
                continue;
            }
            seenIds[id] = true;

            records.push({
                type: "app",
                apps: [],
                previewIcons: [],
                persistent: {type: "app", id},
                id,
                title,
                icon: String(sourceModel.data(modelIndex, decorationRole) ?? "application-x-executable"),
                description: String(sourceModel.data(modelIndex, descriptionRole) ?? ""),
                sourceRow: row,
                url: String(sourceModel.data(modelIndex, urlRole) ?? ""),
            });
        }
        return records;
    }

    function _appById(appId) {
        return applicationById[appId] ?? null;
    }

    function isApplicationRunning(appId) {
        runningRevision;
        return runningApplications.isRunning(appId);
    }

    function _previewIcons(memberIds) {
        const icons = [];
        for (const appId of memberIds) {
            const app = _appById(appId);
            if (app && app.icon) {
                icons.push(app.icon);
            }
            if (icons.length === 4) {
                break;
            }
        }
        return icons;
    }

    function synchronize(): void {
        if (!sourceModel) {
            return;
        }

        const previousFolderIds = Object.keys(folderRows);
        applications = _readSourceApplications();
        // First occurrence wins so a duplicated storage ID always resolves to
        // the same source row that the visible (deduplicated) entry used.
        const applicationIndex = Object.create(null);
        for (const app of applications) {
            if (applicationIndex[app.id] === undefined) {
                applicationIndex[app.id] = app;
            }
        }
        applicationById = applicationIndex;
        const result = LayoutStore.reconcile(serializedLayout, applications, defaultFolderName);

        const rows = result.layout.map(item => item.type === "folder"
            ? _newFolderMap(item.id, item.title, item.apps)
            : applicationIndex[item.id]);
        _publishLayout(rows);
        for (const folderId of previousFolderIds) {
            if (folderRows[folderId] === undefined) {
                folderRemoved(folderId);
            }
        }
        revision += 1;

        if (result.changed || serializedLayout !== result.serialized) {
            serializedLayout = result.serialized;
            persistenceTimer.restart();
        }
    }

    function _publishLayout(rows): void {
        const counts = Object.create(null);
        const folders = Object.create(null);
        const indices = Object.create(null);
        for (let row = 0; row < rows.length; ++row) {
            const item = rows[row];
            indices[item.id] = row;
            if (item.type === "folder") {
                counts[item.id] = item.apps.length;
                folders[item.id] = row;
            }
        }
        // All record mutations have finished before notifying the view.
        layoutState = {rows, folderCounts: counts, folderRows: folders, rootRowsById: indices};
    }

    function _plainRootEntry(index) {
        if (index < 0 || index >= layoutRows.length) {
            return null;
        }
        return layoutRows[index];
    }

    function rootEntryAt(index) {
        revision;
        return _plainRootEntry(index);
    }

    function searchEntryAt(index) {
        searchRevision;
        return searchController.entryAt(index);
    }

    function folderEntryAt(folderId, index) {
        revision;
        const folderRow = _folderRow(folderId);
        if (folderRow < 0) {
            return null;
        }
        const folder = layoutRows[folderRow];
        if (!folder || index < 0 || index >= folder.apps.length) {
            return null;
        }
        return _appById(folder.apps[index]);
    }

    function entryAt(mode, index, folderId) {
        if (mode === "search") {
            return searchEntryAt(index);
        }
        if (mode === "folder") {
            return folderEntryAt(folderId, index);
        }
        return rootEntryAt(index);
    }

    function countFor(mode, folderId) {
        if (mode === "search") {
            return searchController.count;
        }
        if (mode === "folder") {
            const count = folderCounts[folderId];
            return count === undefined ? 0 : count;
        }
        return rootCount;
    }

    function _folderRow(folderId) {
        const row = folderRows[folderId];
        return row === undefined ? -1 : row;
    }

    function folderName(folderId) {
        revision;
        const row = _folderRow(folderId);
        return row < 0 ? "" : layoutRows[row].title;
    }

    function folderCount(folderId) {
        revision;
        const count = folderCounts[folderId];
        return count === undefined ? 0 : count;
    }

    function _folderMembers(folderRow) {
        const folder = _plainRootEntry(folderRow);
        return folder && folder.type === "folder" ? folder.apps.slice() : [];
    }

    function _updateFolder(rows, folderRow, name, members): void {
        const folder = rows[folderRow];
        if (folder && folder.type === "folder") {
            rows[folderRow] = _newFolderMap(folder.id, String(name), members);
        }
    }

    function _newFolderMap(folderId, name, members) {
        return {
            type: "folder",
            id: folderId,
            title: name,
            icon: "folder",
            description: "",
            sourceRow: -1,
            url: "",
            apps: members,
            previewIcons: _previewIcons(members),
            persistent: {type: "folder", id: folderId, name, apps: members},
        };
    }

    function _makeFolderId() {
        return `folder-${Date.now().toString(36)}-${Math.floor(Math.random() * 0x1000000).toString(36)}`;
    }

    function _markLayoutChanged(rows): void {
        // Keep the serialized snapshot in sync immediately; only the write to
        // the plasmoid configuration is debounced. A stale snapshot would let
        // a synchronize() that runs inside the debounce window (application
        // churn, hide, restore) drop just-made user edits.
        _publishLayout(rows);
        serializedLayout = _serializeCurrentLayout();
        revision += 1;
        persistenceTimer.restart();
    }

    function _serializeCurrentLayout() {
        // Persistent records are created with their immutable display record,
        // so drag commits only serialize references, without hydrating and
        // sanitizing every application again on the release frame.
        return JSON.stringify({version: LayoutStore.CURRENT_VERSION,
            items: layoutRows.map(item => item.persistent)});
    }

    function activate(mode, index, folderId): void {
        const entry = entryAt(mode, index, folderId);
        activateEntry(entry);
    }

    function activateEntry(entry): void {
        if (!entry) {
            return;
        }
        if (entry.type === "folder") {
            if (_folderRow(entry.id) >= 0) {
                folderOpenRequested(entry.id);
            }
        } else if (entry.type === "runner") {
            if (searchController.trigger(entry, "", undefined)) {
                interactionConcluded();
            }
        } else {
            launchApplication(entry.id);
        }
    }

    function launchApplication(appId): void {
        const app = _appById(appId);
        if (!app || !sourceModel) {
            return;
        }
        if (sourceModel.trigger(app.sourceRow, "", undefined)) {
            searchController.recordLaunch(appId);
            applicationLaunched(appId);
        }
    }

    function actionsFor(appId) {
        const app = _appById(appId);
        if (!app || !sourceModel) {
            return [];
        }

        const modelIndex = sourceModel.index(app.sourceRow, 0);
        if (!sourceModel.data(modelIndex, hasActionListRole)) {
            return [];
        }

        const actions = sourceModel.data(modelIndex, actionListRole);
        return _filterApplicationActions(actions ? Array.from(actions) : []);
    }

    function _filterApplicationActions(actions) {
        const filtered = [];
        for (const action of actions) {
            // Kicker exposes its own hide action when the applet has a
            // hiddenApplications setting. App Grid owns that operation so it
            // can atomically remove the app from folders, search, and layout;
            // suppress Kicker's duplicate menu item.
            if (String(action.actionId ?? "") === "hideApplication") {
                continue;
            }
            const isSeparator = action.type === "separator";
            if (isSeparator && (filtered.length === 0
                    || filtered[filtered.length - 1].type === "separator")) {
                continue;
            }
            filtered.push(action);
        }
        while (filtered.length > 0
                && filtered[filtered.length - 1].type === "separator") {
            filtered.pop();
        }
        return filtered;
    }

    function actionsForEntry(entry) {
        if (!entry) {
            return [];
        }
        if (entry.type === "runner") {
            return searchController.actionsFor(entry);
        }
        return entry.type === "app" ? actionsFor(entry.id) : [];
    }

    function triggerAction(appId, actionId, argument): void {
        const app = _appById(appId);
        if (!app || !sourceModel || !actionId) {
            return;
        }

        if (sourceModel.trigger(app.sourceRow, actionId, argument)) {
            // These Kicker actions launch this app. Editing its desktop file,
            // pinning it or opening software details must not teach a habit.
            if (actionId === "_kicker_jumpListAction" || actionId === "_kicker_recentDocument") {
                searchController.recordLaunch(appId);
            }
            interactionConcluded();
        }
    }

    function triggerEntryAction(entry, actionId, argument): void {
        if (!entry) {
            return;
        }
        if (entry.type === "runner") {
            if (searchController.trigger(entry, actionId, argument)) {
                interactionConcluded();
            }
            return;
        }
        if (entry.type === "app") {
            triggerAction(entry.id, actionId, argument);
        }
    }

    function restoreHiddenApplications(): void {
        if (hiddenApplicationCount > 0) {
            restoreHiddenApplicationsRequested();
        }
    }

    function hideApplication(appId): void {
        const id = String(appId ?? "");
        if (!id || !hiddenApplications || hiddenApplications.includes(id)) {
            return;
        }
        // A fresh array is required so the change handler observes the edit.
        hiddenApplications = hiddenApplications.concat([id]);
    }

    function moveRootItem(from, to): void {
        if (from < 0 || from >= rootCount || rootCount < 2) {
            return;
        }
        const target = Math.max(0, Math.min(to, rootCount - 1));
        if (from === target) {
            return;
        }
        const rows = layoutRows.slice();
        rows.splice(target, 0, rows.splice(from, 1)[0]);
        _markLayoutChanged(rows);
    }

    function _createFolderFromRoot(sourceIndex, targetIndex): void {
        const source = _plainRootEntry(sourceIndex);
        const target = _plainRootEntry(targetIndex);
        if (!source || !target || source.type !== "app" || target.type !== "app" || source.id === target.id) {
            return;
        }
        const rows = layoutRows.slice();
        rows[targetIndex] = _newFolderMap(_makeFolderId(), defaultFolderName, [target.id, source.id]);
        rows.splice(sourceIndex, 1);
        _markLayoutChanged(rows);
    }

    function _addRootAppToFolder(sourceIndex, folderId): void {
        const source = _plainRootEntry(sourceIndex);
        const folderRow = _folderRow(folderId);
        if (!source || source.type !== "app" || folderRow < 0) {
            return;
        }
        const rows = layoutRows.slice();
        const members = _folderMembers(folderRow);
        if (!members.includes(source.id)) {
            members.push(source.id);
        }
        _updateFolder(rows, folderRow, rows[folderRow].title, members);
        rows.splice(sourceIndex, 1);
        _markLayoutChanged(rows);
    }

    function indexOfEntry(mode, entryId, folderId): int {
        if (mode === "folder") {
            const folder = _plainRootEntry(_folderRow(folderId));
            return folder ? folder.apps.indexOf(entryId) : -1;
        }
        if (mode === "root") {
            return rootRowsById[entryId] ?? -1;
        }
        return -1;
    }

    function dropRootItem(sourceIndex, targetIndex, dropOnTarget): void {
        const source = _plainRootEntry(sourceIndex);
        const target = _plainRootEntry(targetIndex);
        if (!source) {
            return;
        }
        if (dropOnTarget && target && source.type === "app") {
            if (target.type === "folder") {
                _addRootAppToFolder(sourceIndex, target.id);
                return;
            }
            if (target.type === "app" && sourceIndex !== targetIndex) {
                _createFolderFromRoot(sourceIndex, targetIndex);
                return;
            }
        }
        moveRootItem(sourceIndex, targetIndex);
    }

    function reorderFolder(folderId, from, to): void {
        const folderRow = _folderRow(folderId);
        const members = _folderMembers(folderRow);
        if (from < 0 || from >= members.length || members.length < 2) {
            return;
        }
        const target = Math.max(0, Math.min(to, members.length - 1));
        if (from === target) {
            return;
        }
        members.splice(target, 0, members.splice(from, 1)[0]);
        const rows = layoutRows.slice();
        _updateFolder(rows, folderRow, rows[folderRow].title, members);
        _markLayoutChanged(rows);
    }

    function removeFromFolder(folderId, appId, rootIndex): void {
        const folderRow = _folderRow(folderId);
        const members = _folderMembers(folderRow);
        const memberIndex = members.indexOf(appId);
        const app = _appById(appId);
        if (folderRow < 0 || memberIndex < 0 || !app) {
            return;
        }
        members.splice(memberIndex, 1);
        const rows = layoutRows.slice();
        const folderWasRemoved = members.length === 0;
        if (folderWasRemoved) {
            rows.splice(folderRow, 1);
        } else {
            _updateFolder(rows, folderRow, rows[folderRow].title, members);
        }
        const insertion = rootIndex === undefined || rootIndex < 0
            ? Math.min(folderRow + (folderWasRemoved ? 0 : 1), rows.length)
            : Math.max(0, Math.min(rootIndex, rows.length));
        rows.splice(insertion, 0, app);
        _markLayoutChanged(rows);
        if (folderWasRemoved) {
            folderRemoved(folderId);
        }
    }

    function renameFolder(folderId, name): void {
        const folderRow = _folderRow(folderId);
        const trimmed = String(name ?? "").trim();
        if (folderRow < 0 || !trimmed || layoutRows[folderRow].title === trimmed) {
            return;
        }
        const rows = layoutRows.slice();
        _updateFolder(rows, folderRow, trimmed, _folderMembers(folderRow));
        _markLayoutChanged(rows);
    }

    function unpackFolder(folderId): void {
        const folderRow = _folderRow(folderId);
        if (folderRow < 0) {
            return;
        }
        const members = _folderMembers(folderRow).map(appId => _appById(appId)).filter(Boolean);
        const rows = layoutRows.slice();
        rows.splice(folderRow, 1, ...members);
        _markLayoutChanged(rows);
        folderRemoved(folderId);
    }
}
