import QtQuick
import QtTest
import org.kde.plasma.appgrid.core as Core
import "../package/contents/code/LayoutStore.js" as LayoutStore

TestCase {
    id: testCase
    name: "NativeSearchIndex"
    Core.SearchIndex { id: index }

    function test_rankingMatchesIndependentJavaScriptOracle() {
        const apps = [];
        for (let row = 0; row < 400; ++row) {
            apps.push({id: `app-${row}.desktop`, title: ["Café", "CAFETERIA", "终端", "日本語", "Éditeur", "Terminal"][row % 6] + ` ${row}`,
                description: row % 3 ? "Office café applications" : "网络 utility", sourceRow: row});
        }
        index.applications = apps;
        const oracle = LayoutStore.buildSearchIndex(apps);
        for (const descriptions of [false, true]) {
            for (const query of ["", "  ", "cafe", "CAFÉ", "é", "终端", "日本語", "网络", "utility 3",
                                 "desktop", "office 1", " app-7 ", "terminal\t2", "not-found"]) {
                const expected = LayoutStore.searchIndexed(oracle, query, descriptions);
                index.search(query, descriptions);
                compare(index.count, expected.length, query);
                for (let row = 0; row < expected.length; ++row) {
                    compare(index.entryAt(row).id, expected[row].id, `${query}, row ${row}`);
                    compare(index.entryAt(row).sourceRow, expected[row].sourceRow);
                    verify(index.contains(expected[row].id));
                }
            }
        }
    }

    function test_recordsStayStableAndCatalogReplacementInvalidatesCache() {
        index.applications = [{id: "alpha", title: "Alpha", sourceRow: 1}, {id: "beta", title: "Beta", sourceRow: 0}];
        verify(index.search("a", true));
        const alpha = index.entryAt(0);
        compare(alpha.type, "app");
        compare(alpha.icon, "application-x-executable");
        compare(alpha.apps.length, 0);
        verify(index.search("alp", true));
        verify(index.entryAt(0) === alpha);
        verify(!index.search("ALP ", true));
        verify(!index.contains("beta"));
        verify(index.application("alpha") === alpha);
        compare(index.entryAt(-1), null);
        compare(index.entryAt(99), null);

        index.applications = [{id: "alpha", title: "Alpha updated", sourceRow: 7}];
        verify(index.search("alp", true));
        verify(index.entryAt(0) !== alpha);
        compare(index.entryAt(0).sourceRow, 7);
        compare(index.entryAt(0).title, "Alpha updated");
        compare(index.application("beta"), null);
    }

    function test_duplicateStorageIdsResolveToFirstSourceRow() {
        index.applications = [{id: "same", title: "First", sourceRow: 0}, {id: "same", title: "Second", sourceRow: 1}];
        index.search("same", true);
        compare(index.count, 1);
        compare(index.entryAt(0).title, "First");
        index.applications = [];
        verify(index.search("same", true));
        compare(index.count, 0);
        verify(!index.contains("same"));
    }
}
