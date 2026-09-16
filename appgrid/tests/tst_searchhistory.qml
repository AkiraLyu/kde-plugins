import QtQuick
import QtTest
import org.kde.plasma.appgrid.core as Core

TestCase {
    id: testCase
    name: "SearchHistory"

    readonly property var apps: [
        {id: "exact.desktop", title: "Term"},
        {id: "short.desktop", title: "Terminal"},
        {id: "long.desktop", title: "Terminal Pro"},
        {id: "description.desktop", title: "Console", description: "Terminal utility"},
        {id: "other.desktop", title: "Unrelated"},
    ]

    Core.SearchIndex { id: index }
    Component { id: indexComponent; Core.SearchIndex {} }
    SignalSpy { id: resultSpy; target: index; signalName: "resultsChanged" }

    function init() {
        index.historyData = "";
        index.historyEnabled = true;
        index.applications = apps.slice();
        index.search("", true);
        resultSpy.clear();
    }

    function history(items): string {
        return JSON.stringify({version: 1, apps: items});
    }

    function usage(id, weight, daysAgo): var {
        return {id, weight, lastUsed: Math.floor(Date.now() / 1000) - daysAgo * 86400};
    }

    function ids(): string {
        const results = [];
        for (let row = 0; row < index.count; ++row) {
            results.push(index.entryAt(row).id);
        }
        return results.join(",");
    }

    function test_learningRespectsTextQualityAndMatchingSet() {
        verify(index.recordLaunch("long.desktop"));
        for (let launch = 0; launch < 40; ++launch) {
            verify(index.recordLaunch("description.desktop"));
            verify(index.recordLaunch("other.desktop"));
        }
        index.search("term", true);
        compare(ids(), "exact.desktop,long.desktop,short.desktop,description.desktop");
        index.search("terminal", true);
        compare(ids(), "short.desktop,long.desktop,description.desktop");
        index.search("term", false);
        compare(ids(), "exact.desktop,long.desktop,short.desktop");
        index.search("unmatched", true);
        compare(index.count, 0);
        index.search("", true);
        compare(index.count, 0);
    }

    function test_frequencyAndRecencyBothInfluenceEqualMatches() {
        index.historyData = history([
            usage("short.desktop", 1, 0), usage("long.desktop", 4, 0),
        ]);
        index.search("term", true);
        compare(index.entryAt(1).id, "long.desktop");

        index.historyData = history([
            usage("short.desktop", 4, 0), usage("long.desktop", 4, 2),
        ]);
        index.search("term", true);
        compare(index.entryAt(1).id, "short.desktop");

        // A recent new habit can replace a previously frequent but old one.
        index.historyData = history([
            usage("short.desktop", 32, 60), usage("long.desktop", 1, 0),
        ]);
        index.search("term", true);
        compare(index.entryAt(1).id, "long.desktop");
    }

    function test_activeQueryAndResultObjectsStayStableAfterLearning() {
        index.search("term", true);
        const oldFirst = index.entryAt(1);
        const learned = index.entryAt(2);
        resultSpy.clear();
        verify(index.recordLaunch("long.desktop"));
        compare(resultSpy.count, 0);
        verify(!index.search("TERM ", true));
        verify(index.entryAt(1) === oldFirst);
        compare(index.historyScoreFor("long.desktop"), 0);

        index.search("ter", true);
        verify(index.entryAt(0) === learned);
        verify(index.historyScoreFor("long.desktop") > 0);
        index.search("", true);
        index.search("term", true);
        verify(index.entryAt(1) === learned);
    }

    function test_historyRestoresBeforeTheCatalogAndAcrossInstances() {
        index.recordLaunch("long.desktop");
        index.recordLaunch("long.desktop");
        const saved = index.historyData;
        const restored = createTemporaryObject(indexComponent, testCase, {historyData: saved});
        verify(restored !== null);
        compare(restored.historyCount, 1);
        restored.applications = apps.slice();
        restored.search("term", true);
        compare(restored.entryAt(1).id, "long.desktop");
        compare(restored.historyData, saved);

        // Source rows may move or disappear temporarily; identity is the ID.
        restored.applications = [];
        restored.search("term", true);
        compare(restored.count, 0);
        compare(restored.historyData, saved);
        restored.applications = apps.slice().reverse();
        restored.search("term", true);
        compare(restored.entryAt(1).id, "long.desktop");
    }

    function test_disableStopsLearningAndClearRestoresOriginalOrder() {
        index.recordLaunch("long.desktop");
        const saved = index.historyData;
        index.historyEnabled = false;
        verify(!index.recordLaunch("short.desktop"));
        compare(index.historyData, saved);
        index.search("term", true);
        compare(index.entryAt(1).id, "short.desktop");
        compare(index.historyScoreFor("long.desktop"), 0);

        index.historyEnabled = true;
        index.search("term", true);
        compare(index.entryAt(1).id, "long.desktop");
        index.historyData = "";
        index.search("term", true);
        compare(index.entryAt(1).id, "short.desktop");
        compare(index.historyCount, 0);
    }

    function test_invalidOrUnknownAppCannotBeRecorded() {
        for (const id of ["", "missing.desktop", "runner:calculator", "LONG.DESKTOP"]) {
            verify(!index.recordLaunch(id));
        }
        compare(index.historyCount, 0);
        compare(index.historyData, "");
    }

    function test_invalidStorage_data() {
        return [
            {tag: "broken", value: "{bad json"},
            {tag: "array", value: "[]"},
            {tag: "future schema", value: JSON.stringify({version: 2, apps: [usage("long.desktop", 1, 0)]})},
            {tag: "wrong types", value: JSON.stringify({version: 1, apps: [null, 3, {id: 42, weight: 1, lastUsed: 10}]})},
            {tag: "oversized", value: " ".repeat(1024 * 1024 + 1)},
        ];
    }

    function test_invalidStorage(data) {
        index.recordLaunch("long.desktop");
        index.historyData = data.value;
        compare(index.historyCount, 0);
        compare(index.historyData, "");
        index.search("term", true);
        compare(index.entryAt(1).id, "short.desktop");
        verify(index.recordLaunch("long.desktop"));
    }

    function test_importPrunesExpiredAndInvalidRowsAndCollapsesDuplicates() {
        index.historyData = history([
            usage("long.desktop", 2, 1), usage("long.desktop", 1000000, 0),
            usage("short.desktop", 1, 91), usage("future.desktop", 1, -100),
            usage("zero.desktop", 0, 0), usage("negative.desktop", -1, 0),
            usage("", 1, 0), usage("x".repeat(1025), 1, 0),
            {id: "wrong.desktop", weight: "one", lastUsed: "today"},
        ]);
        compare(index.historyCount, 1);
        const stored = JSON.parse(index.historyData);
        compare(stored.apps[0].id, "long.desktop");
        compare(stored.apps[0].weight, 32);
        compare(Object.keys(stored.apps[0]).sort().join(","), "id,lastUsed,weight");
    }

    function test_historyCapacityKeepsNewLaunchesAndPreservesUnicodeIds() {
        const entries = [];
        for (let row = 0; row < 600; ++row) {
            entries.push(usage(`app-${row}.desktop`, 32, 1));
        }
        index.historyData = history(entries);
        compare(index.historyCount, 512);
        index.applications = [{id: "终端-É.desktop", title: "Terminal"}];
        verify(index.recordLaunch("终端-É.desktop"));
        compare(index.historyCount, 512);
        verify(JSON.parse(index.historyData).apps.some(app => app.id === "终端-É.desktop"));
        index.search("term", true);
        verify(index.historyScoreFor("终端-É.desktop") > 0);
        compare(index.entryAt(0).id, "终端-É.desktop");
    }
}
