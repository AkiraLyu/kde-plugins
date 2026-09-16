import QtQuick
import QtTest

import "../package/contents/code/LayoutStore.js" as LayoutStore

TestCase {
    name: "LayoutStore"

    readonly property var apps: [
        {id: "alpha.desktop", title: "Alpha", icon: "alpha", description: "Drawing", sourceRow: 0, url: "applications:alpha.desktop"},
        {id: "beta.desktop", title: "Beta Tool", icon: "beta", description: "System utility", sourceRow: 1, url: "applications:beta.desktop"},
        {id: "gamma.desktop", title: "Gamma", icon: "gamma", description: "Office editor", sourceRow: 2, url: "applications:gamma.desktop"},
    ]

    function test_emptyLayoutUsesKdeOrder() {
        const result = LayoutStore.reconcile("", apps, "Folder");
        compare(result.layout.length, 3);
        compare(result.layout[0].id, "alpha.desktop");
        compare(result.layout[2].id, "gamma.desktop");
    }

    function test_reconcilePreservesOrderAndAppendsNewApps() {
        const stored = JSON.stringify({
            version: 1,
            items: [
                {type: "app", id: "beta.desktop"},
                {type: "app", id: "alpha.desktop"},
            ],
        });
        const result = LayoutStore.reconcile(stored, apps, "Folder");
        compare(result.layout.map(item => item.id).join(","),
                "beta.desktop,alpha.desktop,gamma.desktop");
    }

    function test_reconcileDropsMissingAndDuplicateApps() {
        const stored = JSON.stringify({
            version: 1,
            items: [
                {type: "app", id: "missing.desktop"},
                {type: "app", id: "alpha.desktop"},
                {type: "app", id: "alpha.desktop"},
            ],
        });
        const result = LayoutStore.reconcile(stored, apps.slice(0, 1), "Folder");
        compare(result.layout.length, 1);
        compare(result.layout[0].id, "alpha.desktop");
        verify(result.changed);
    }

    function test_folderOwnsAppsAndSurvivesWithOneMember() {
        const stored = JSON.stringify({
            version: 1,
            items: [
                {type: "folder", id: "tools", name: "Tools", apps: ["beta.desktop", "missing.desktop"]},
                {type: "app", id: "beta.desktop"},
                {type: "app", id: "alpha.desktop"},
            ],
        });
        const result = LayoutStore.reconcile(stored, apps.slice(0, 2), "Folder");
        compare(result.layout.length, 2);
        compare(result.layout[0].type, "folder");
        compare(result.layout[0].apps.length, 1);
        compare(result.layout[0].apps[0], "beta.desktop");
        compare(result.layout[1].id, "alpha.desktop");
    }

    function test_emptyFolderIsRemoved() {
        const stored = JSON.stringify({
            version: 1,
            items: [
                {type: "folder", id: "old", name: "Old", apps: ["missing.desktop"]},
            ],
        });
        const result = LayoutStore.reconcile(stored, apps.slice(0, 1), "Folder");
        compare(result.layout.length, 1);
        compare(result.layout[0].type, "app");
    }

    function test_corruptDataRecovers() {
        const result = LayoutStore.reconcile("{broken", apps, "Folder");
        compare(result.layout.length, 3);
        verify(result.changed);
    }

    function test_searchRanksTitleBeforeDescription() {
        const searchable = [
            {id: "one.desktop", title: "Editor", description: "Utility", sourceRow: 0},
            {id: "two.desktop", title: "Utility", description: "Editor", sourceRow: 1},
        ];
        const result = LayoutStore.search(searchable, "editor", true);
        compare(result.length, 2);
        compare(result[0].id, "one.desktop");
    }

    function test_searchMatchesEveryToken() {
        const result = LayoutStore.search(apps, "beta system", true);
        compare(result.length, 1);
        compare(result[0].id, "beta.desktop");
    }

    function test_largeCatalogRemainsDeterministic() {
        const catalog = [];
        for (let index = 0; index < 5000; ++index) {
            catalog.push({
                id: `application-${index}.desktop`,
                title: `Application ${index}`,
                icon: "application-x-executable",
                description: index === 4096 ? "Needle utility" : "Fixture",
                sourceRow: index,
                url: `applications:application-${index}.desktop`,
            });
        }

        const reconciled = LayoutStore.reconcile("", catalog, "Folder");
        compare(reconciled.layout.length, 5000);
        compare(reconciled.layout[4096].id, "application-4096.desktop");

        const result = LayoutStore.search(catalog, "needle", true);
        compare(result.length, 1);
        compare(result[0].id, "application-4096.desktop");
    }
}
