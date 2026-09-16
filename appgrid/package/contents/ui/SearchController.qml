pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.appgrid.core as Core

QtObject {
    id: root

    property var applications: []
    property var applicationById: ({})
    property var appletInterface: null
    property string query: ""
    property bool includeDescriptions: true
    property bool runnerSearchEnabled: true
    property bool historyEnabled: true
    property string historyData: ""
    readonly property int historyCount: localSearch.historyCount
    property int maximumRunnerResults: 48
    property var runners: [
        "krunner_services",
        "krunner_systemsettings",
        "krunner_sessions",
        "krunner_powerdevil",
        "calculator",
        "unitconverter",
    ]

    // runnerSource is replaceable so the merge and activation behavior can
    // be tested without starting real KRunner plugins.
    property var runnerSource: internalRunnerModel
    // Only secondary results live in QML. The native index owns the full
    // local result order and lazily materializes records for visible slots.
    property var resultState: ({providers: [], localCount: 0, revision: 0})
    readonly property var results: resultState.providers
    readonly property int localCount: resultState.localCount
    readonly property int revision: resultState.revision
    property bool runnerResultsReady: false

    readonly property int count: resultState.localCount + resultState.providers.length
    readonly property bool querying: runnerSearchEnabled
        && query.trim().length > 0
        && runnerSource !== null
        && (queryTimer.running || Boolean(runnerSource.querying))
    readonly property var matchesModel: runnerSource !== null
        && Number(runnerSource.count ?? 0) > 0
        ? runnerSource.modelForRow(0) : null

    signal queryReplacementRequested(string query)
    signal historyPersistenceRequested(string serialized)

    readonly property int displayRole: 0
    readonly property int decorationRole: 1
    readonly property int groupRole: 258
    readonly property int descriptionRole: 257
    readonly property int favoriteIdRole: 259
    readonly property int hasActionListRole: 264
    readonly property int actionListRole: 265
    readonly property int urlRole: 266

    property Kicker.RunnerModel internalRunnerModel: Kicker.RunnerModel {
        appletInterface: root.appletInterface
        mergeResults: true
        runners: root.runners
    }

    property Core.SearchIndex localSearch: Core.SearchIndex {
        historyEnabled: root.historyEnabled
    }

    property Timer queryTimer: Timer {
        interval: 55
        repeat: false
        onTriggered: root._startQuery()
    }

    property Timer rebuildTimer: Timer {
        interval: 0
        repeat: false
        onTriggered: root._rebuildResults()
    }

    property Connections runnerConnections: Connections {
        target: root.runnerSource
        enabled: root.runnerSource !== null
        ignoreUnknownSignals: true

        function onAnyRunnerFinished(): void {
            root._acceptRunnerResults();
        }

        function onQueryFinished(): void {
            root._acceptRunnerResults();
        }

        function onCountChanged(): void {
            root._scheduleRunnerRebuild();
        }

        function onRequestUpdateQuery(query): void {
            root.queryReplacementRequested(String(query));
        }
    }

    property Connections matchesConnections: Connections {
        target: root.matchesModel
        enabled: root.matchesModel !== null
        ignoreUnknownSignals: true

        function onModelReset(): void {
            root._scheduleRunnerRebuild();
        }

        function onRowsInserted(): void {
            root._scheduleRunnerRebuild();
        }

        function onRowsRemoved(): void {
            root._scheduleRunnerRebuild();
        }

        function onDataChanged(): void {
            root._scheduleRunnerRebuild();
        }

        function onRequestUpdateQueryString(query): void {
            // On current Plasma releases this signal is emitted by the
            // merged RunnerMatchesModel rather than its RunnerModel parent.
            root.queryReplacementRequested(String(query));
        }
    }

    onApplicationsChanged: _rebuildApplicationSearchIndex()
    onApplicationByIdChanged: rebuildTimer.restart()
    onQueryChanged: _handleQueryChange()
    onIncludeDescriptionsChanged: rebuildTimer.restart()
    onRunnerSearchEnabledChanged: _handleQueryChange()
    onRunnerSourceChanged: _handleQueryChange()
    onHistoryDataChanged: _loadHistory()
    onHistoryEnabledChanged: rebuildTimer.restart()

    Component.onCompleted: {
        _loadHistory();
        _rebuildApplicationSearchIndex();
    }

    function _loadHistory(): void {
        if (localSearch.historyData !== historyData) {
            localSearch.historyData = historyData;
            rebuildTimer.restart();
        }
    }

    function recordLaunch(appId): void {
        if (localSearch.recordLaunch(String(appId))) {
            // Publish the bounded serialized snapshot only after a launch.
            // Matching and provider updates never write configuration, and
            // the current query keeps its order until the next query.
            historyData = localSearch.historyData;
            // Hand off before the launcher can be destroyed. Plasma owns
            // disk persistence; no timer can overwrite a subsequent clear.
            historyPersistenceRequested(historyData);
        }
    }

    function _normalizedApplicationId(value) {
        let id = String(value ?? "").trim();
        if (!id) {
            return "";
        }
        id = id.replace(/^applications:/, "");
        while (id.startsWith("/")) {
            id = id.slice(1);
        }
        const suffixOffset = id.search(/[?#]/);
        if (suffixOffset >= 0) {
            id = id.slice(0, suffixOffset);
        }
        return id;
    }

    function _runnerEntry(model, row, ordinal) {
        const index = model.index(row, 0);
        const title = String(model.data(index, displayRole) ?? "");
        const description = String(model.data(index, descriptionRole) ?? "");
        const category = String(model.data(index, groupRole) ?? "");
        const url = String(model.data(index, urlRole) ?? "");
        const runnerKey = `${category}\u0000${title}\u0000${description}\u0000${url}`;
        return {
            type: "runner",
            id: `runner-${ordinal}-${title}-${url}`,
            title,
            icon: model.data(index, decorationRole) ?? "system-search",
            description,
            category,
            url,
            apps: [],
            previewIcons: [],
            runnerRow: row,
            runnerModel: model,
            runnerKey,
            runnerQuery: query,
        };
    }

    function _runnerKeyAt(model, row) {
        if (!model || row < 0 || row >= Number(model.count ?? 0)) {
            return "";
        }
        const index = model.index(row, 0);
        return `${String(model.data(index, groupRole) ?? "")}\u0000`
            + `${String(model.data(index, displayRole) ?? "")}\u0000`
            + `${String(model.data(index, descriptionRole) ?? "")}\u0000`
            + String(model.data(index, urlRole) ?? "");
    }

    function _resolveRunnerRow(entry): int {
        if (!entry || !entry.runnerModel || !_runnerResultsAreCurrent()
                || entry.runnerQuery !== query || entry.runnerModel !== matchesModel) {
            return -1;
        }
        const model = entry.runnerModel;
        if (_runnerKeyAt(model, entry.runnerRow) === entry.runnerKey) {
            return entry.runnerRow;
        }
        const count = Number(model.count ?? 0);
        for (let row = 0; row < count; ++row) {
            if (_runnerKeyAt(model, row) === entry.runnerKey) {
                return row;
            }
        }
        return -1;
    }

    function _handleQueryChange(): void {
        // Local application matching is cheap and should follow each
        // keystroke without the KRunner debounce. Do not clear and recreate
        // the KRunner model for every intermediate character: unpublished
        // results are guarded by the exact query in _acceptRunnerResults().
        runnerResultsReady = false;
        if (runnerSource !== null
                && (!runnerSearchEnabled || query.trim().length === 0)) {
            runnerSource.query = "";
        }
        rebuildTimer.stop();
        _rebuildResults();
        if (runnerSearchEnabled && runnerSource !== null && query.trim()) {
            queryTimer.restart();
        } else {
            queryTimer.stop();
        }
    }

    function _rebuildApplicationSearchIndex(): void {
        localSearch.applications = applications;
        rebuildTimer.restart();
    }

    function _runnerResultsAreCurrent(): bool {
        return runnerResultsReady && runnerSearchEnabled
            && runnerSource !== null && query.trim().length > 0
            && String(runnerSource.query ?? "") === query;
    }

    function _scheduleRunnerRebuild(): void {
        // RunnerModel emits several reset/count/data signals while replacing
        // a query. None of those intermediate snapshots are displayed, so
        // rebuilding local results for each one only churns every icon slot.
        if (_runnerResultsAreCurrent()) {
            rebuildTimer.restart();
        }
    }

    function _acceptRunnerResults(): void {
        // RunnerModel cancels the preceding query, but individual plugin
        // completion signals can still arrive while the replacement query is
        // inside our debounce window. Only publish matches whose source still
        // carries the exact query currently displayed in the search field.
        if (!runnerSearchEnabled || runnerSource === null
                || String(runnerSource.query ?? "") !== query
                || query.trim().length === 0) {
            return;
        }
        runnerResultsReady = true;
        rebuildTimer.restart();
    }

    function _startQuery(): void {
        const text = query.trim();
        runnerResultsReady = false;

        if (runnerSource !== null) {
            const nextQuery = runnerSearchEnabled && text.length > 0
                ? query : "";
            if (String(runnerSource.query ?? "") !== nextQuery) {
                runnerSource.query = nextQuery;
            } else if (nextQuery && !runnerSource.querying) {
                // Typing then backspacing within the debounce can return to
                // an already completed query. It will not finish a second time.
                _acceptRunnerResults();
            }
        }
    }

    function _entryKey(entry): string {
        if (!entry) {
            return "";
        }
        return entry.type === "runner"
            ? `runner:${String(entry.runnerKey ?? entry.id ?? "")}`
            : `app:${String(entry.id ?? "")}`;
    }

    function _entriesEquivalent(left, right): bool {
        if (!left || !right || left.type !== right.type
                || left.id !== right.id || left.title !== right.title
                || left.icon !== right.icon
                || left.description !== right.description
                || left.category !== right.category
                || left.url !== right.url
                || left.sourceRow !== right.sourceRow) {
            return false;
        }
        if (left.type === "runner") {
            return left.runnerKey === right.runnerKey
                && left.runnerModel === right.runnerModel
                && left.runnerQuery === right.runnerQuery;
        }
        return true;
    }

    function _commitResults(nextResults, localChanged): void {
        const previousByKey = Object.create(null);
        for (const previous of results) {
            previousByKey[_entryKey(previous)] = previous;
        }

        const stableResults = [];
        for (const next of nextResults) {
            const previous = previousByKey[_entryKey(next)];
            stableResults.push(_entriesEquivalent(previous, next)
                ? previous : next);
        }

        if (!localChanged && stableResults.length === results.length) {
            let changed = false;
            for (let index = 0; index < stableResults.length; ++index) {
                if (stableResults[index] !== results[index]) {
                    changed = true;
                    break;
                }
            }
            if (!changed) {
                return;
            }
        }

        resultState = {providers: stableResults, localCount: localSearch.count, revision: revision + 1};
    }

    function _rebuildResults(): void {
        const text = query.trim();
        const localChanged = localSearch.search(text, includeDescriptions);
        if (!text) {
            _commitResults([], localChanged);
            return;
        }

        const runnerAppResults = [];
        const externalResults = [];
        const seenApplications = Object.create(null);
        const seenExternal = Object.create(null);

        const model = _runnerResultsAreCurrent() ? matchesModel : null;
        const runnerCount = model ? Number(model.count ?? 0) : 0;
        // Bound role reads as well as published results. Some providers return
        // thousands of duplicates; none may monopolize an input frame.
        const scanLimit = Math.min(runnerCount, maximumRunnerResults * 4);
        for (let row = 0; row < scanLimit; ++row) {
            if (runnerAppResults.length + externalResults.length >= maximumRunnerResults) {
                break;
            }
            const index = model.index(row, 0);
            const favoriteId = _normalizedApplicationId(
                model.data(index, favoriteIdRole));
            if (favoriteId) {
                // The services runner can return hidden/NoDisplay entries.
                // Only promote results that survived the KDE application
                // model and this launcher's hidden-app filter.
                const app = applicationById[favoriteId];
                if (app && !localSearch.contains(favoriteId) && !seenApplications[favoriteId]) {
                    seenApplications[favoriteId] = true;
                    runnerAppResults.push({entry: localSearch.application(favoriteId),
                        historyScore: localSearch.historyScoreFor(favoriteId), ordinal: row});
                }
                continue;
            }

            const entry = _runnerEntry(model, row, externalResults.length);
            if (!entry.title) {
                continue;
            }
            const key = `${entry.category}\u0000${entry.title}\u0000${entry.description}\u0000${entry.url}`;
            if (seenExternal[key]) {
                continue;
            }
            seenExternal[key] = true;
            externalResults.push(entry);
            if (externalResults.length >= maximumRunnerResults) {
                break;
            }
        }

        // GNOME's search keeps applications ahead of secondary providers.
        // KRunner-discovered application keyword matches follow direct local
        // matches. Apply the same history snapshot within those app results;
        // settings/calculator/session results retain KRunner's relevance order.
        runnerAppResults.sort((a, b) => b.historyScore - a.historyScore || a.ordinal - b.ordinal);
        _commitResults(runnerAppResults.map(result => result.entry).concat(externalResults), localChanged);
    }

    function entryAt(index) {
        const state = resultState;
        if (index < 0 || index >= state.localCount + state.providers.length) {
            return null;
        }
        return index < state.localCount ? localSearch.entryAt(index) : state.providers[index - state.localCount];
    }

    function actionsFor(entry) {
        if (!entry || entry.type !== "runner" || !entry.runnerModel) {
            return [];
        }
        const model = entry.runnerModel;
        const row = _resolveRunnerRow(entry);
        if (row < 0) {
            return [];
        }
        const index = model.index(row, 0);
        if (!model.data(index, hasActionListRole)) {
            return [];
        }
        const actions = model.data(index, actionListRole);
        return actions ? Array.from(actions) : [];
    }

    function trigger(entry, actionId, argument) {
        if (!entry || entry.type !== "runner" || !entry.runnerModel) {
            return false;
        }
        const row = _resolveRunnerRow(entry);
        return row >= 0 && entry.runnerModel.trigger(
            row, String(actionId ?? ""), argument);
    }
}
