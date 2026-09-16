import QtQuick
import QtTest

import "../package/contents/ui"

TestCase {
    id: testCase

    name: "SearchController"

    readonly property var applications: [
        {
            id: "alpha.desktop",
            title: "Alpha",
            icon: "applications-graphics",
            description: "Drawing",
            sourceRow: 0,
            url: "applications:alpha.desktop",
        },
        {
            id: "beta.desktop",
            title: "Beta",
            icon: "applications-system",
            description: "System utility",
            sourceRow: 1,
            url: "applications:beta.desktop",
        },
    ]
    readonly property var applicationIndex: ({
        "alpha.desktop": applications[0],
        "beta.desktop": applications[1],
    })

    QtObject {
        id: fakeMatches

        property var records: []
        readonly property int count: records.length
        property int lastTriggeredRow: -1
        property string lastActionId: ""
        property var lastActionArgument: null
        property bool triggerResult: true

        signal modelReset()
        signal requestUpdateQueryString(string query)

        function index(row, column) {
            return {row};
        }

        function data(modelIndex, role) {
            const record = records[modelIndex.row];
            switch (role) {
            case 0: return record.title;
            case 1: return record.icon;
            case 258: return record.category ?? "";
            case 257: return record.description ?? "";
            case 259: return record.favoriteId ?? "";
            case 264: return (record.actions ?? []).length > 0;
            case 265: return record.actions ?? [];
            case 266: return record.url ?? "";
            default: return undefined;
            }
        }

        function trigger(row, actionId, argument) {
            lastTriggeredRow = row;
            lastActionId = actionId;
            lastActionArgument = argument;
            return triggerResult;
        }
    }

    QtObject {
        id: fakeRunner

        property string query: ""
        property bool querying: false
        readonly property int count: 1

        signal anyRunnerFinished()
        signal queryFinished()
        signal requestUpdateQuery(string query)

        function modelForRow(row) {
            return row === 0 ? fakeMatches : null;
        }
    }

    SearchController {
        id: searchController
        applications: testCase.applications
        applicationById: testCase.applicationIndex
        runnerSource: fakeRunner
    }

    SignalSpy {
        id: replacementSpy
        target: searchController
        signalName: "queryReplacementRequested"
    }

    function init() {
        searchController.query = "";
        searchController.runnerSearchEnabled = true;
        searchController.historyData = "";
        searchController.historyEnabled = true;
        fakeRunner.query = "";
        fakeRunner.querying = false;
        fakeMatches.records = [];
        fakeMatches.lastTriggeredRow = -1;
        fakeMatches.lastActionId = "";
        fakeMatches.lastActionArgument = null;
        fakeMatches.triggerResult = true;
        replacementSpy.clear();
        wait(70);
    }

    function test_localResultsAppearBeforeRunnerProviders() {
        fakeMatches.records = [
            {
                title: "Alpha runner duplicate",
                favoriteId: "applications:alpha.desktop",
            },
            {
                title: "Beta keyword match",
                favoriteId: "applications:/beta.desktop?action=ignored",
            },
            {
                title: "Hidden service",
                favoriteId: "applications:hidden.desktop",
            },
            {
                title: "Display Configuration",
                icon: "preferences-desktop-display",
                description: "System Settings",
                category: "System Settings",
                url: "applications:kcm_displayconfiguration.desktop",
            },
            {
                title: "42",
                icon: "accessories-calculator",
                description: "6 × 7",
                category: "Calculator",
            },
        ];

        searchController.query = "alpha";
        compare(searchController.count, 1);
        compare(searchController.entryAt(0).id, "alpha.desktop");
        tryCompare(fakeRunner, "query", "alpha", 500);
        fakeRunner.anyRunnerFinished();
        tryCompare(searchController, "count", 4, 500);

        compare(searchController.entryAt(0).id, "alpha.desktop");
        compare(searchController.entryAt(1).id, "beta.desktop");
        compare(searchController.entryAt(2).title, "Display Configuration");
        compare(searchController.entryAt(3).title, "42");
        compare(searchController.entryAt(2).type, "runner");
    }

    function test_historyRanksKeywordAppsAndPreservesProviderResults() {
        searchController.recordLaunch("beta.desktop");
        fakeMatches.records = [
            {title: "Setting", category: "System Settings", url: "settings:display"},
            {title: "Alpha keyword", favoriteId: "alpha.desktop"},
            {title: "Beta keyword", favoriteId: "applications:beta.desktop"},
            {title: "Calculator answer", category: "Calculator", url: "calculator:42"},
        ];
        searchController.query = "keyword";
        wait(70);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 4, 500);
        compare(searchController.entryAt(0).id, "beta.desktop");
        compare(searchController.entryAt(1).id, "alpha.desktop");
        compare(searchController.entryAt(2).title, "Setting");
        compare(searchController.entryAt(3).title, "Calculator answer");

        // Late provider signals cannot shuffle a query as it is being used.
        const first = searchController.entryAt(0);
        for (let launch = 0; launch < 4; ++launch) {
            searchController.recordLaunch("alpha.desktop");
        }
        const revision = searchController.revision;
        fakeMatches.modelReset();
        wait(0);
        compare(searchController.revision, revision);
        verify(searchController.entryAt(0) === first);

        const saved = searchController.historyData;
        verify(searchController.trigger(searchController.entryAt(2), "", null));
        compare(searchController.historyData, saved);
        searchController.query = "keyword updated";
        wait(70);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 4, 500);
        compare(searchController.entryAt(0).id, "alpha.desktop");
        searchController.historyData = "";
        tryCompare(searchController, "historyCount", 0, 500);
        wait(0);
        compare(searchController.entryAt(0).id, "alpha.desktop");
    }

    function test_newQueryImmediatelyHidesPreviousRunnerResults() {
        fakeMatches.records = [{
            title: "Display Configuration",
            category: "System Settings",
        }];

        searchController.query = "display";
        tryCompare(fakeRunner, "query", "display", 500);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 1, 500);
        compare(searchController.entryAt(0).type, "runner");

        searchController.query = "beta";
        // The old provider query may finish during the short debounce, but
        // its rows are unpublished and therefore cannot replace local hits.
        compare(fakeRunner.query, "display");
        compare(searchController.count, 1);
        compare(searchController.entryAt(0).id, "beta.desktop");

        // A late completion from the cancelled "display" query must not
        // append its stale provider row during the replacement debounce.
        fakeRunner.queryFinished();
        wait(0);
        compare(searchController.count, 1);
        compare(searchController.entryAt(0).id, "beta.desktop");
    }

    function test_completedQueryReturnsAfterBackspacingWithinDebounce() {
        fakeMatches.records = [{title: "Calculator answer", category: "Calculator"}];
        searchController.query = "alpha";
        tryCompare(fakeRunner, "query", "alpha", 500);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 2, 500);
        searchController.query = "alphax";
        searchController.query = "alpha";
        tryCompare(searchController, "count", 2, 500);
        compare(searchController.entryAt(1).title, "Calculator answer");
    }

    function test_oldRunnerEntryCannotActivateAfterQueryChanges() {
        fakeMatches.records = [{title: "Old answer", category: "Calculator"}];
        searchController.query = "alpha";
        tryCompare(fakeRunner, "query", "alpha", 500);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 2, 500);
        const stale = searchController.entryAt(1);
        searchController.query = "beta";
        compare(searchController.trigger(stale, "", null), false);
        compare(fakeMatches.lastTriggeredRow, -1);
    }

    function test_queryRefinementDoesNotRepublishIdenticalLocalRows() {
        searchController.query = "b";
        compare(searchController.count, 1);
        const initialRevision = searchController.revision;
        const initialEntry = searchController.entryAt(0);

        searchController.query = "be";
        compare(searchController.count, 1);
        compare(searchController.revision, initialRevision);
        verify(searchController.entryAt(0) === initialEntry);

        // Starting the debounced provider query must not publish the exact
        // same local row a second time.
        wait(70);
        compare(fakeRunner.query, "be");
        compare(searchController.revision, initialRevision);
        verify(searchController.entryAt(0) === initialEntry);
    }

    function test_runnerDebounceCountsAsQuerying() {
        searchController.query = "external-only";
        verify(searchController.querying);
        tryCompare(fakeRunner, "query", "external-only", 500);

        fakeRunner.querying = true;
        verify(searchController.querying);
        fakeRunner.querying = false;
        compare(searchController.querying, false);
    }

    function test_servicesUrlWithoutASlashMapsToTheCanonicalApp() {
        fakeMatches.records = [{
            title: "Beta keyword match",
            favoriteId: "applications:beta.desktop",
        }];

        searchController.query = "keyword-without-local-match";
        tryCompare(fakeRunner, "query", "keyword-without-local-match", 500);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 1, 500);
        compare(searchController.entryAt(0).type, "app");
        compare(searchController.entryAt(0).id, "beta.desktop");
    }

    function test_runnerActionsAndActivationStayOnSourceRow() {
        const actionArgument = {mode: "advanced"};
        fakeMatches.records = [{
            title: "Display Configuration",
            icon: "preferences-desktop-display",
            category: "System Settings",
            actions: [{
                text: "Open Module",
                actionId: "runnerAction",
                actionArgument,
            }],
        }];

        searchController.query = "display";
        tryCompare(fakeRunner, "query", "display", 500);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 1, 500);

        const entry = searchController.entryAt(0);
        compare(searchController.actionsFor(entry).length, 1);
        verify(searchController.trigger(entry, "runnerAction", actionArgument));
        compare(fakeMatches.lastTriggeredRow, 0);
        compare(fakeMatches.lastActionId, "runnerAction");
        compare(fakeMatches.lastActionArgument.mode, "advanced");
    }

    function test_runnerActivationResolvesAReorderedMatch() {
        fakeMatches.records = [{
            title: "Display Configuration",
            icon: "preferences-desktop-display",
            category: "System Settings",
            url: "applications:kcm_displayconfiguration.desktop",
        }];

        searchController.query = "display";
        tryCompare(fakeRunner, "query", "display", 500);
        fakeRunner.queryFinished();
        tryCompare(searchController, "count", 1, 500);
        const staleEntry = searchController.entryAt(0);

        fakeMatches.records = [{
            title: "Another Result",
            category: "System Settings",
        }, fakeMatches.records[0]];
        verify(searchController.trigger(staleEntry, "", undefined));
        compare(fakeMatches.lastTriggeredRow, 1);
    }

    function test_disabledRunnerSearchClearsRunnerQuery() {
        searchController.query = "beta";
        tryCompare(fakeRunner, "query", "beta", 500);

        searchController.runnerSearchEnabled = false;
        tryCompare(fakeRunner, "query", "", 500);
        tryCompare(searchController, "count", 1, 500);
        compare(searchController.entryAt(0).id, "beta.desktop");
    }

    function test_runnerModelCanRequestAReplacementQuery() {
        fakeRunner.requestUpdateQuery("2 + 2");
        compare(replacementSpy.count, 1);
        compare(replacementSpy.signalArguments[0][0], "2 + 2");
    }

    function test_matchesModelCanRequestAReplacementQuery() {
        fakeMatches.requestUpdateQueryString("10 cm in inches");
        compare(replacementSpy.count, 1);
        compare(replacementSpy.signalArguments[0][0], "10 cm in inches");
    }
}
