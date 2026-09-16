pragma ComponentBehavior: Bound

import QtQuick
import QtTest

import "../package/contents/ui"
import "../package/contents/code/LayoutStore.js" as LayoutStore

TestCase {
    id: testCase

    name: "PerformanceTelemetry"

    width: 1536
    height: 864
    when: windowShown

    readonly property var fixtureCounts: [250, 1000, 5000]
    property bool recordFrames: false
    property var frameTimes: []

    FrameAnimation {
        running: testCase.recordFrames
        onTriggered: {
            if (currentFrame > 4) {
                testCase.frameTimes.push(frameTime * 1000);
            }
        }
    }

    QtObject {
        id: fakeModel

        property var records: []
        readonly property int count: records.length

        signal modelReset()

        function index(row, column) {
            return {row};
        }

        function data(modelIndex, role) {
            const record = records[modelIndex.row];
            switch (role) {
            case 0: return record.title;
            case 1: return record.icon;
            case 257: return record.description;
            case 259: return record.id;
            case 264: return false;
            case 265: return [];
            case 266: return `applications:${record.id}`;
            default: return undefined;
            }
        }

        function trigger(row, actionId, argument) {
            return row >= 0 && row < count;
        }
    }

    AppGridStyle {
        id: appGridStyle
        requestedIconSize: 96
    }

    LayoutController {
        id: controller
        runningTrackingEnabled: false
        enableKRunnerSearch: false
        defaultFolderName: "Folder"
    }

    AppGridView {
        id: view
        anchors.fill: parent
        style: appGridStyle
        controller: controller
    }

    SignalSpy {
        id: historyPersistSpy
        target: controller
        signalName: "launchHistoryPersistenceRequested"
    }

    function seedHistory(): void {
        const apps = [];
        const now = Math.floor(Date.now() / 1000);
        for (let row = 0; row < 512; ++row) {
            apps.push({id: `application-${4999 - row}.desktop`,
                weight: 1 + row % 32, lastUsed: now - row * 3600});
        }
        controller.launchHistoryData = JSON.stringify({version: 1, apps});
    }

    function makeFixtures(total): var {
        const records = [];
        const categories = [
            "Graphics", "System", "Office", "Multimedia", "Development",
            "Games", "Education", "Network", "Utilities", "Science",
        ];
        for (let index = 0; index < total; ++index) {
            const category = categories[index % categories.length];
            records.push({
                id: `application-${index}.desktop`,
                title: `${category} Application ${index}`,
                icon: "application-x-executable",
                description: `Fixture ${category.toLowerCase()} number ${index}`,
            });
        }
        return records;
    }

    function countSlots(item): int {
        let total = 0;
        for (let child = 0; child < item.children.length; ++child) {
            const candidate = item.children[child];
            if (candidate instanceof GridSlot) {
                total += 1;
            }
            total += countSlots(candidate);
        }
        return total;
    }

    function initTestCase() {
        failOnWarning(/TypeError/);
    }

    function init() {
        console.info("perf: init start");
        controller.sourceModel = null;
        console.info("perf: model cleared");
        controller.serializedLayout = "";
        controller.searchText = "";
        controller.launchHistoryData = "";
        historyPersistSpy.clear();
        controller.hiddenApplications = [];
        console.info("perf: state reset");
        view.reset();
        console.info("perf: init done");
    }

    function cleanup() {
        recordFrames = false;
    }

    function reportFrames(label): void {
        recordFrames = false;
        verify(frameTimes.length > 10, "too few rendered animation frames");
        frameTimes.sort((a, b) => a - b);
        const median = frameTimes[Math.floor(frameTimes.length / 2)];
        const p95 = frameTimes[Math.floor(frameTimes.length * 0.95)];
        const worst = frameTimes[frameTimes.length - 1];
        console.info(`${label}: frames=${frameTimes.length}, median=${median.toFixed(2)}ms, `
            + `p95=${p95.toFixed(2)}ms, max=${worst.toFixed(2)}ms`);
        // Allow scheduler/vsync jitter; the synchronous input test separately
        // gates work inside a 16 ms frame. This catches sustained rendering stalls.
        verify(p95 < 40 && worst < 100, `${label} stalled: p95=${p95}ms, max=${worst}ms`);
    }

    function prepareFrameFixture(): void {
        testCase.visible = true;
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        seedHistory();
        view.reset();
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        waitForRendering(view);
        frameTimes = [];
        recordFrames = true;
    }

    function test_renderedTypingFrames() {
        prepareFrameFixture();
        for (let pass = 0; pass < 3; ++pass) {
            for (const query of ["a", "ap", "app", "application", "application 4",
                                 "application 49", "application 499", "missing", "app", ""]) {
                view.searchText = query;
                wait(48);
            }
        }
        reportFrames("typingFrames(5000 apps, 512 remembered)");
        compare(historyPersistSpy.count, 0);
    }

    function test_renderedDragReorderAndMergeFrames() {
        prepareFrameFixture();
        const grid = view.grid;
        const source = grid.liveSlots.find(slot => slot.globalIndex === 0).tile;
        const start = source.captureVisual(view).center;
        const cell = grid.itemRect(3);
        const target = grid.mapToItem(view, cell.x + cell.width * 0.08, cell.y + cell.height / 2);
        mousePress(view, start.x, start.y, Qt.LeftButton);
        for (let step = 1; step <= 24; ++step) {
            mouseMove(view, start.x + (target.x - start.x) * step / 24,
                start.y + (target.y - start.y) * step / 24, 16, Qt.LeftButton);
        }
        verify(grid.dragging);
        wait(appGridStyle.dragReorderDelay + appGridStyle.dragShiftDuration + 40);
        verify(grid.reorderPreviewActive);
        mouseRelease(view, target.x, target.y, Qt.LeftButton);
        wait(appGridStyle.dragSettleDuration + 40);
        compare(controller.rootEntryAt(3).id, "application-0.desktop");

        const moved = grid.liveSlots.find(slot => slot.globalIndex === 3).tile;
        const nextStart = moved.captureVisual(view).center;
        const mergeCell = grid.itemRect(4);
        const mergePoint = grid.mapToItem(view, mergeCell.x + mergeCell.width / 2,
            mergeCell.y + mergeCell.height / 2);
        mousePress(view, nextStart.x, nextStart.y, Qt.LeftButton);
        mouseMove(view, nextStart.x + 40, nextStart.y, 16, Qt.LeftButton);
        mouseMove(view, mergePoint.x, mergePoint.y, 16, Qt.LeftButton);
        wait(appGridStyle.dragMergeDelay + 40);
        verify(grid.mergeArmed);
        mouseRelease(view, mergePoint.x, mergePoint.y, Qt.LeftButton);
        wait(appGridStyle.dragMergeDuration + 40);
        compare(controller.count, 4999);
        compare(controller.rootEntryAt(3).type, "folder");
        reportFrames("dragFrames(5000 apps, 512 remembered)");
        compare(historyPersistSpy.count, 0);
    }

    // Keep synchronization within the latency budget for each fixture count
    // and print timings to make performance regressions visible.
    function test_synchronizeScalesWithApplicationCount() {
        const bounds = {250: 400, 1000: 800, 5000: 2500};
        controller.sourceModel = fakeModel;
        for (const total of fixtureCounts) {
            fakeModel.records = makeFixtures(total);

            const started = Date.now();
            fakeModel.modelReset();
            const synchronizeMillis = Date.now() - started;

            compare(controller.count, total);
            verify(synchronizeMillis < bounds[total],
                `${total} apps synchronized in ${synchronizeMillis}ms`);
            console.info(`synchronize(${total}) = ${synchronizeMillis}ms`);
        }
    }

    // Icon delegates must scale with the visible page area, never with the
    // installed-application count.
    function test_delegateCountStaysBounded() {
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        view.reset();
        tryCompare(controller, "count", 5000, 2500);

        const pageSize = view.grid.pageSize;
        const slots = countSlots(view.grid);
        verify(slots > 0 && slots <= pageSize * 5,
            `expected at most ${pageSize * 5} slots for 5000 apps, found ${slots}`);
        console.info(`gridSlots(5000 apps) = ${slots}, pageSize = ${pageSize}`);
    }

    function test_searchDelegateCountStaysBounded() {
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        view.reset();
        view.searchText = "application";
        tryCompare(controller, "searchCount", 5000, 2500);
        tryCompare(view.grid, "itemCount", 5000, 2500);
        wait(0);

        const pageSize = view.grid.pageSize;
        const slots = countSlots(view.grid);
        verify(slots > 0 && slots <= pageSize * 5,
            `expected at most ${pageSize * 5} search slots, found ${slots}`);
        console.info(`searchGridSlots(5000 hits) = ${slots}`);
    }

    function test_dragDoesNotInstantiateTheWholeCatalog() {
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        view.reset();
        tryCompare(controller, "count", 5000, 2500);
        const grid = view.grid;
        const origin = grid.liveSlots.find(slot => slot.globalIndex === 0);
        verify(origin);
        origin.dragStateChanged(true);
        try {
            wait(0);
            verify(grid.pageCacheBuffer <= grid.width * 2);
            verify(grid.liveSlotCount <= grid.pageSize * 4);
            grid.goToPage(20, false);
            wait(0);
            verify(grid.liveSlots.includes(origin), "drag source was recycled");
            verify(grid.liveSlotCount <= grid.pageSize * 5,
                `drag created ${grid.liveSlotCount} slots`);
            console.info(`dragGridSlots(5000 apps, page 20) = ${grid.liveSlotCount}`);
        } finally {
            origin.dragStateChanged(false);
            grid.reset();
        }
    }

    // The in-memory search runs synchronously over the full application
    // index; keep it comfortably interactive for pathological counts.
    function test_searchLatencyForLargeIndex() {
        const records = makeFixtures(5000);
        const indexStarted = Date.now();
        const searchIndex = LayoutStore.buildSearchIndex(records);
        const indexMillis = Date.now() - indexStarted;

        let started = Date.now();
        let results = LayoutStore.searchIndexed(
            searchIndex, "science 4999", true);
        const firstMillis = Date.now() - started;

        compare(results.length, 1);
        compare(results[0].id, "application-4999.desktop");
        verify(firstMillis < 600, `first search took ${firstMillis}ms`);

        started = Date.now();
        results = LayoutStore.searchIndexed(
            searchIndex, "application", true);
        const broadMillis = Date.now() - started;

        compare(results.length, 5000);
        verify(broadMillis < 1500, `broad search took ${broadMillis}ms`);
        console.info(`searchIndex(5000) = ${indexMillis}ms, `
            + `search(5000, first) = ${firstMillis}ms, `
            + `search(5000, 5000 hits) = ${broadMillis}ms`);
    }

    function test_typingLatencyWithVisibleResults_data() {
        return [{tag: "no-history", remembered: false}, {tag: "remembered", remembered: true}];
    }

    function test_typingLatencyWithVisibleResults(data) {
        testCase.visible = true;
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        if (data.remembered) {
            seedHistory();
        }
        view.reset();
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const queries = ["a", "ap", "app", "appl", "application", "application 4",
            "application 49", "application 499", "no-such-application", "app", ""];
        const samples = [];
        for (let pass = 0; pass < 3; ++pass) {
            for (const query of queries) {
                const started = Date.now();
                view.searchText = query;
                samples.push(Date.now() - started);
                wait(0);
            }
        }
        samples.sort((a, b) => a - b);
        const median = samples[Math.floor(samples.length / 2)];
        const p95 = samples[Math.floor(samples.length * 0.95)];
        const worst = samples[samples.length - 1];
        console.info(`typing(5000 apps, history=${data.remembered}): median=${median}ms, p95=${p95}ms, max=${worst}ms`);
        verify(p95 < 16 && worst < 32, `typing blocked the GUI: p95=${p95}ms, max=${worst}ms`);
        compare(historyPersistSpy.count, 0);
    }

    function test_largeLayoutMutationsStayWithinAFrame() {
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        seedHistory();
        view.reset();
        wait(0);
        const source = controller.rootEntryAt(0);
        let started = Date.now();
        controller.moveRootItem(0, 20);
        const reorder = Date.now() - started;
        compare(controller.rootEntryAt(20).id, source.id);
        started = Date.now();
        controller.dropRootItem(20, 2, true);
        const merge = Date.now() - started;
        compare(controller.count, 4999);
        verify(controller.rootEntryAt(2).apps.includes(source.id));
        console.info(`mutate(5000 apps): reorder=${reorder}ms, merge=${merge}ms`);
        verify(reorder < 32 && merge < 32, `layout mutation stalled: ${reorder}/${merge}ms`);
        compare(JSON.parse(controller.serializedLayout).items.length, 4999);
    }

    function test_firstPageSurvivesResultCountChangesAndEmptySearch() {
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        seedHistory();
        view.reset();
        wait(0);
        const first = view.grid.liveSlots.find(slot => slot.globalIndex === 0);
        const firstTile = first.tile;
        const neighbor = view.grid.liveSlots.find(slot => slot.globalIndex === view.grid.pageSize);
        const neighborTile = neighbor.tile;
        for (const query of ["application", "application 499", "missing", "application", ""]) {
            view.searchText = query;
            wait(0);
            verify(view.grid.liveSlots.includes(first), `first page recreated for ${query}`);
            verify(first.tile === firstTile, `first icon delegate recreated for ${query}`);
            verify(view.grid.liveSlots.includes(neighbor), `warm neighbor recreated for ${query}`);
            verify(neighbor.tile === neighborTile, `warm neighbor icon recreated for ${query}`);
        }
    }

    function test_recordingHistoryStaysWithinAFrame() {
        fakeModel.records = makeFixtures(5000);
        controller.sourceModel = fakeModel;
        seedHistory();
        wait(0);
        let worst = 0;
        for (let row = 0; row < 32; ++row) {
            const started = Date.now();
            controller.launchApplication(`application-${row}.desktop`);
            worst = Math.max(worst, Date.now() - started);
        }
        console.info(`recordLaunch(512 remembered): max=${worst}ms`);
        verify(worst < 16, `recording history stalled a frame: ${worst}ms`);
        compare(JSON.parse(controller.launchHistoryData).apps.length, 512);
        compare(historyPersistSpy.count, 32);
    }
}
