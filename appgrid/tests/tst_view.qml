import QtQuick
import QtTest

import "../package/contents/ui"

TestCase {
    id: testCase

    name: "AppGridView"
    width: 1536
    height: 864
    when: windowShown

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
            case 264: return record.actions !== undefined && record.actions.length > 0;
            case 265: return record.actions ?? [];
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
        enableKRunnerSearch: false
        runningTrackingEnabled: false
        defaultFolderName: "Folder"
    }

    AppGridView {
        id: view
        anchors.fill: parent
        style: appGridStyle
        controller: controller
    }

    AppActionMenu {
        id: actionMenu
        visualParent: view
        controller: controller
        entry: {
            controller.revision;
            return controller.count > 0 ? controller.rootEntryAt(0) : null;
        }
        sourceMode: "root"
    }

    PageDots {
        id: pageDotsFixture
        opacity: 0
        style: appGridStyle
    }

    SignalSpy {
        id: menuHideSpy
        target: actionMenu
        signalName: "hideRequested"
    }

    SignalSpy {
        id: exitFinishedSpy
        target: view
        signalName: "exitFinished"
    }

    SignalSpy {
        id: applicationLaunchedSpy
        target: controller
        signalName: "applicationLaunched"
    }

    Component.onCompleted: {
        const applications = [];
        for (let index = 0; index < 31; ++index) {
            applications.push({
                id: `application-${index}.desktop`,
                title: index === 0
                    ? "Application 0 With A Long Multiline Name"
                    : `Application ${index}`,
                icon: "application-x-executable",
                description: `Fixture ${index}`,
                actions: index === 0 ? [{
                    text: "Open New Window",
                    icon: "window-new",
                    actionId: "new-window",
                }] : [],
            });
        }
        fakeModel.records = applications;
        controller.sourceModel = fakeModel;
        view.reset();
    }

    function initTestCase() {
        failOnWarning(/TypeError/);
        failOnWarning(/setRunning\(\)|Binding loop/);
    }

    function init() {
        testCase.visible = false;
        testCase.width = 1536;
        testCase.height = 864;
        wait(0);
        view.searchText = "";
        controller.launchHistoryData = "";
        controller.serializedLayout = "";
        controller.synchronize();
        view.reset();
        actionMenu.menuEntry = null;
        menuHideSpy.clear();
        exitFinishedSpy.clear();
        applicationLaunchedSpy.clear();
    }

    function cleanup() {
        testCase.visible = false;
    }

    function test_adaptiveSixByFourGeometry() {
        compare(view.width, 1536);
        compare(view.height, 864);
        compare(view.grid.columns, 6);
        compare(view.grid.rows, 4);
        compare(view.grid.pageSize, 24);
        compare(view.grid.pageCount, 2);
    }

    function test_multilineApplicationLabelStaysInsideSelectionFrame() {
        const tile = findTile(findSlot(view.grid, 0));
        verify(tile);
        const label = findChild(tile, "appGridApplicationLabel");
        const frame = findChild(tile, "appGridTileBackground");
        verify(label && frame);
        verify(label.lineCount >= 2);

        const labelBottom = label.mapToItem(tile, 0, label.height).y;
        const frameBottom = frame.mapToItem(tile, 0, frame.height).y;
        verify(labelBottom <= frameBottom - frame.border.width - 2,
            `label bottom ${labelBottom} exceeds frame content bottom ${frameBottom}`);
    }

    function test_adaptiveGeometryAcrossLogicalScreenSizes() {
        const fixtures = [
            {width: 1280, height: 720, columns: 6, rows: 3},
            {width: 1024, height: 600, columns: 5, rows: 3},
            {width: 2560, height: 1440, columns: 6, rows: 4},
            {width: 3440, height: 1440, columns: 8, rows: 3},
            {width: 1200, height: 1800, columns: 4, rows: 6},
        ];

        for (const fixture of fixtures) {
            testCase.width = fixture.width;
            testCase.height = fixture.height;
            wait(0);
            compare(view.grid.columns, fixture.columns,
                `columns at ${fixture.width}x${fixture.height}`);
            compare(view.grid.rows, fixture.rows,
                `rows at ${fixture.width}x${fixture.height}`);
            verify(view.grid.cellWidth > 0 && view.grid.cellHeight > 0);
        }

        testCase.width = 1536;
        testCase.height = 864;
        wait(0);
    }

    function test_resizeKeepsTheSelectedApplicationVisible() {
        view.grid.selectIndex(30);
        tryCompare(view.grid, "currentPage", 1, 500);

        testCase.width = 1024;
        testCase.height = 600;
        tryCompare(view.grid, "pageSize", 15, 500);
        tryCompare(view.grid, "currentPage", 2, 500);
        compare(view.grid.selectedIndex, 30);

        testCase.width = 1536;
        testCase.height = 864;
        tryCompare(view.grid, "pageSize", 24, 500);
        tryCompare(view.grid, "currentPage", 1, 500);
    }

    function test_searchAndPageChurnRemainStable() {
        view.searchText = "Application 30";
        tryCompare(controller, "searchCount", 1, 500);
        tryCompare(view.grid, "itemCount", 1, 500);
        compare(view.grid.selectedIndex, 0);

        view.searchText = "";
        tryCompare(view.grid, "itemCount", 31, 500);
        view.grid.goToPage(1, true);
        tryCompare(view.grid, "currentPage", 1, 600);
        view.grid.goToPage(0, false);
        compare(view.grid.currentPage, 0);
    }

    function test_eachSearchQueryReturnsToTheFirstPage() {
        view.searchText = "Application";
        tryCompare(view.grid, "itemCount", 31, 500);
        view.grid.goToPage(1, false);
        compare(view.grid.currentPage, 1);

        // Descriptions contain "Fixture", producing the same result count;
        // reset must therefore follow the query, not count changes alone.
        view.searchText = "Fixture";
        tryCompare(view.grid, "currentPage", 0, 500);
        compare(view.grid.itemCount, 31);
    }

    function test_exitAndEntranceTransitionsReachStableStates() {
        view.playEntrance();
        compare(view.contentScale, appGridStyle.overviewInitialScale);
        wait(Math.max(20,
            Math.floor(appGridStyle.entranceScaleDuration / 2)));
        verify(view.contentScale > appGridStyle.overviewInitialScale);
        verify(view.contentScale < 1);
        tryCompare(view, "transitionRunning", false, 800);
        compare(view.backdropOpacity, 1);
        compare(view.contentOpacity, 1);
        compare(view.contentScale, 1);

        view.playExit();
        verify(view.transitionRunning);
        tryCompare(exitFinishedSpy, "count", 1, 800);
        compare(view.backdropOpacity, 0);
        compare(view.contentOpacity, 0);
        compare(view.contentScale, appGridStyle.overviewExitScale);

        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        compare(view.backdropOpacity, 1);
        compare(view.contentOpacity, 1);
        compare(view.contentScale, 1);
    }

    function test_runnerQueryReplacementUpdatesTheSearchField() {
        controller.searchText = "6 * 7";
        compare(view.searchText, "6 * 7");
        compare(controller.searchText, "6 * 7");
    }

    function test_homeEditsAQueryAndControlHomeNavigatesResults() {
        view.searchText = "Application";
        tryCompare(view.grid, "itemCount", 31, 500);
        wait(0);
        view.grid.selectIndex(7);
        view.keyEventProxy.cursorPosition = 5;
        view.keyEventProxy.forceActiveFocus(Qt.OtherFocusReason);

        keyClick(Qt.Key_Home);
        compare(view.keyEventProxy.cursorPosition, 0);
        compare(view.grid.selectedIndex, 7);

        keyClick(Qt.Key_Home, Qt.ControlModifier);
        compare(view.grid.selectedIndex, 0);
    }

    function test_leftRightNavigateSearchResultsWhileInputKeepsFocus() {
        view.searchText = "Application";
        tryCompare(view.grid, "itemCount", 31, 500);
        wait(0);
        const input = view.keyEventProxy;
        verify(input);
        input.cursorPosition = 5;
        input.forceActiveFocus(Qt.OtherFocusReason);
        view.grid.selectIndex(0);

        keyClick(Qt.Key_Right);
        compare(view.grid.selectedIndex, 1);
        compare(input.cursorPosition, 5);
        verify(input.activeFocus);

        keyClick(Qt.Key_Left);
        compare(view.grid.selectedIndex, 0);
        compare(input.cursorPosition, 5);
        verify(input.activeFocus);

        keyClick(Qt.Key_Right, Qt.ControlModifier);
        compare(view.grid.selectedIndex, 0);
        verify(input.cursorPosition > 5);
        verify(input.activeFocus);
    }

    function test_trackpadPagingTracksThenSettles() {
        const grid = view.grid;
        grid.goToPage(0, false);

        grid.updateTrackpadGesture(grid.width * 0.24);
        verify(grid.trackpadGestureActive);
        verify(grid.pagePosition > 0 && grid.pagePosition < 1);

        grid.settleTrackpadGesture();
        tryCompare(grid, "currentPage", 1, 600);
        compare(grid.pagePosition, 1);
        compare(grid.selectedIndex, grid.pageSize);

        grid.updateTrackpadGesture(-grid.width * 0.03);
        grid.settleTrackpadGesture();
        tryCompare(grid, "currentPage", 1, 600);
    }

    function test_directPagingMovesKeyboardSelectionToTheVisiblePage() {
        const grid = view.grid;
        grid.selectIndex(3);
        grid.goToPage(1, false);
        compare(grid.currentPage, 1);
        compare(grid.selectedIndex, grid.pageSize);

        grid.goToPage(0, false);
        compare(grid.currentPage, 0);
        compare(grid.selectedIndex, 0);
    }

    function test_nonAnimatedPagingCancelsPendingTransition() {
        const grid = view.grid;
        grid.goToPage(0, false);
        grid.goToPage(1, true);
        compare(grid.pageTransitionRunning, true);

        // currentPage is still zero at the beginning of the animation. A
        // request to stay there must nevertheless stop the pending page-one
        // transition instead of returning early and letting it finish later.
        grid.goToPage(0, false);
        compare(grid.pageTransitionRunning, false);
        compare(grid.currentPage, 0);
        compare(grid.pagePosition, 0);
        wait(appGridStyle.pageDuration + 40);
        compare(grid.currentPage, 0);
        compare(grid.pagePosition, 0);
        const firstRect = grid.itemRect(0);
        verify(firstRect.x >= 0 && firstRect.x < grid.width);
    }

    function test_touchStyleActivationSelectsItsTile() {
        const slot = findSlot(view.grid, 6);
        verify(slot);
        view.grid.selectedIndex = 0;

        slot.activated(6);
        compare(view.grid.selectedIndex, 6);
    }

    function test_mouseClickActivatesVisibleApplication() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const itemRect = view.grid.itemRect(6);
        verify(itemRect.width > 0 && itemRect.height > 0);
        const point = view.grid.mapToItem(view,
            itemRect.x + itemRect.width / 2,
            itemRect.y + itemRect.height / 2);
        mouseMove(view, point.x, point.y);
        tryCompare(view.grid, "selectedIndex", 6, 200);
        mouseClick(view, point.x, point.y, Qt.LeftButton);
        tryCompare(applicationLaunchedSpy, "count", 1, 200);
        compare(applicationLaunchedSpy.signalArguments[0][0],
            "application-6.desktop");
    }

    function dragRootItemWithMouse(sourceIndex, targetIndex,
                                   targetXFraction, targetYFraction,
                                   targetHoldMilliseconds = 20,
                                   beforeRelease = null) {
        const sourceTile = findTile(findSlot(view.grid, sourceIndex));
        verify(sourceTile);
        const sourceRect = view.grid.itemRect(sourceIndex);
        const targetRect = view.grid.itemRect(targetIndex);
        verify(sourceRect.width > 0 && sourceRect.height > 0);
        verify(targetRect.width > 0 && targetRect.height > 0);

        // Start from the tile's rendered center, which includes any final
        // fraction of a gap-preview settling animation.
        const sourcePoint = sourceTile.mapToItem(view,
            sourceTile.width / 2, sourceTile.height / 2);
        const targetPoint = view.grid.mapToItem(view,
            targetRect.x + targetRect.width * targetXFraction,
            targetRect.y + targetRect.height * targetYFraction);
        const deltaX = targetPoint.x - sourcePoint.x;
        const deltaY = targetPoint.y - sourcePoint.y;
        const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
        const activationDistance = appGridStyle.pointerDragThreshold + 4;
        verify(distance > activationDistance);
        const activationX = deltaX / distance * activationDistance;
        const activationY = deltaY / distance * activationDistance;

        verify(sourcePoint.x >= 0 && sourcePoint.x < view.width
                && sourcePoint.y >= 0 && sourcePoint.y < view.height,
            `source point is outside the view: ${sourcePoint}`);
        mousePress(view, sourcePoint.x, sourcePoint.y, Qt.LeftButton);
        mouseMove(view,
            sourcePoint.x + activationX * 0.5,
            sourcePoint.y + activationY * 0.5,
            20, Qt.LeftButton);
        mouseMove(view,
            sourcePoint.x + activationX,
            sourcePoint.y + activationY,
            20, Qt.LeftButton);
        tryCompare(view.grid, "dragging", true, 200);
        mouseMove(view,
            sourcePoint.x + deltaX * 0.65,
            sourcePoint.y + deltaY * 0.65,
            20, Qt.LeftButton);
        mouseMove(view, targetPoint.x, targetPoint.y,
            20, Qt.LeftButton);
        wait(targetHoldMilliseconds);
        const releasePoint = beforeRelease
            ? beforeRelease(sourceTile) ?? targetPoint : targetPoint;
        mouseRelease(view, releasePoint.x, releasePoint.y, Qt.LeftButton);
        tryCompare(view.grid, "dragging", false, 200);
        wait(0);
        return sourceTile;
    }

    function test_mouseDragReordersApplications() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        compare(controller.rootEntryAt(0).id, "application-0.desktop");
        compare(controller.rootEntryAt(2).id, "application-2.desktop");
        const targetSlot = findSlot(view.grid, 2);
        verify(targetSlot);
        // The leading edge of a populated cell means reorder, not merge.
        const draggedTile = dragRootItemWithMouse(0, 2, 0.08, 0.5);

        compare(controller.count, 31);
        compare(controller.rootEntryAt(2).id, "application-0.desktop");
        compare(draggedTile.dragReturnAnimationRunning, false);
        compare(draggedTile.dragVisualOffset, Qt.point(0, 0));
        tryCompare(targetSlot, "shiftAnimationRunning", false, 500);
        tryCompare(targetSlot, "renderedShiftOffset", Qt.point(0, 0), 500);
    }

    function test_rememberedSearchKeepsLayoutAndDragMergeBehavior() {
        testCase.visible = true;
        controller.launchHistoryData = JSON.stringify({version: 1, apps: [
            {id: "application-30.desktop", weight: 10, lastUsed: Math.floor(Date.now() / 1000)},
        ]});
        const history = controller.launchHistoryData;
        const layout = controller.serializedLayout;
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const first = findSlot(view.grid, 0);
        view.searchText = "app";
        tryCompare(view.grid, "itemCount", 31, 500);
        compare(first.entry.id, "application-30.desktop");
        compare(controller.serializedLayout, layout);
        view.searchText = "";
        wait(0);
        verify(findSlot(view.grid, 0) === first);
        compare(controller.rootEntryAt(0).id, "application-0.desktop");

        dragRootItemWithMouse(0, 2, 0.08, 0.5,
            appGridStyle.dragReorderDelay + 40);
        compare(controller.rootEntryAt(2).id, "application-0.desktop");
        wait(appGridStyle.dragSettleDuration + 40);
        dragRootItemWithMouse(2, 3, 0.5, 0.5,
            appGridStyle.dragMergeDelay + 40);
        const folder = controller.rootEntryAt(2);
        compare(folder.type, "folder");
        compare(folder.apps.join(","), "application-3.desktop,application-0.desktop");
        compare(controller.launchHistoryData, history);
        compare(applicationLaunchedSpy.count, 0);
    }

    function test_dropContinuesFromRenderedPositions() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        const grid = view.grid;
        let sourceBefore = null;
        let neighborBefore = null;
        dragRootItemWithMouse(0, 4, 0.08, 0.5, 20, source => {
            sourceBefore = source.captureVisual(grid);
            neighborBefore = findSlot(grid, 4).captureVisual(grid);
        });

        const sourceDestination = findSlot(grid, 4);
        const neighborDestination = findSlot(grid, 3);
        compare(sourceDestination.entry.id, sourceBefore.entry.id);
        compare(neighborDestination.entry.id, neighborBefore.entry.id);
        verify(sourceDestination.landingAnimationRunning);
        for (const pair of [[sourceDestination, sourceBefore],
                            [neighborDestination, neighborBefore]]) {
            const rendered = pair[0].captureVisual(grid).center;
            verify(Math.abs(rendered.x - pair[1].center.x) < 8,
                `drop jumped horizontally: ${rendered.x} vs ${pair[1].center.x}`);
            verify(Math.abs(rendered.y - pair[1].center.y) < 8,
                `drop jumped vertically: ${rendered.y} vs ${pair[1].center.y}`);
        }
        tryCompare(sourceDestination, "landingAnimationRunning", false, 700);
        compare(sourceDestination.landingX, 0);
        compare(sourceDestination.landingY, 0);
        compare(sourceDestination.landingScale, 1);
    }

    function test_dragTracksPointerAcrossActivationThreshold() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        // A real Wayland window can finish its initial configure after the
        // entrance timer. Wait for the lazy page's first polish as well.
        tryVerify(() => findSlot(view.grid, 0) !== null, 800);
        const source = findTile(findSlot(view.grid, 0));
        const center = source.captureVisual(view).center;
        const press = source.mapToItem(view, source.width * 0.3,
            source.height * 0.4);
        mousePress(view, press.x, press.y, Qt.LeftButton);
        mouseMove(view, press.x + 50, press.y + 12, 20, Qt.LeftButton);
        tryCompare(source, "dragging", true, 200);
        const lifted = source.captureVisual(view).center;
        verify(Math.abs(lifted.x - center.x - 50) < 2,
            `threshold x: before ${center.x}, after ${lifted.x}, offset ${source.dragGrabOffset}`);
        verify(Math.abs(lifted.y - center.y - 12) < 2,
            `threshold y: before ${center.y}, after ${lifted.y}`);
        mouseMove(view, press.x + 90, press.y + 30, 20, Qt.LeftButton);
        const moved = source.captureVisual(view).center;
        verify(Math.abs(moved.x - lifted.x - 40) < 2);
        verify(Math.abs(moved.y - lifted.y - 18) < 2);
        mouseRelease(view, 10, 10, Qt.LeftButton);
        tryCompare(source, "dragging", false, 200);
    }

    function test_repeatedHoverDoesNotInvalidateEverySlot() {
        const grid = view.grid;
        const origin = findSlot(grid, 0);
        origin.dragStateChanged(true);
        grid.handleSlotDragHover(3, true, false);
        const revision = grid.previewRevision;
        for (let movement = 0; movement < 120; ++movement) {
            grid.handleSlotDragHover(3, true, false);
            grid.handleSlotDragHover(2, false, false);
        }
        compare(grid.previewRevision, revision);
        grid.handleSlotDragHover(3, true, true);
        compare(grid.previewRevision, revision + 1);
        origin.dragStateChanged(false);
    }

    function test_landingCanBePickedUpBeforeItFinishes() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        dragRootItemWithMouse(0, 3, 0.08, 0.5);
        const destination = findSlot(view.grid, 3);
        verify(destination.landingAnimationRunning);
        const tile = findTile(destination);
        const center = tile.captureVisual(view).center;
        // Press the moving icon, not the destination cell underneath it.
        mousePress(view, center.x, center.y, Qt.LeftButton);
        mouseMove(view, center.x + 40, center.y + 12, 1, Qt.LeftButton);
        tryCompare(tile, "dragging", true, 200);
        compare(destination.landingAnimationRunning, false);
        const beforeMove = tile.captureVisual(view).center;
        mouseMove(view, center.x + 70, center.y + 24, 1, Qt.LeftButton);
        const afterMove = tile.captureVisual(view).center;
        mouseRelease(view, 10, 10, Qt.LeftButton);
        verify(Math.abs(afterMove.x - beforeMove.x - 30) < 2);
        verify(Math.abs(afterMove.y - beforeMove.y - 12) < 2);
        compare(controller.rootEntryAt(3).id, "application-0.desktop");
        tryCompare(tile, "dragReturnAnimationRunning", false, 600);
    }

    function test_mergeRequiresAStationaryDwellAndKeepsSmallTremorArmed() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const target = findSlot(view.grid, 1);
        const rect = view.grid.itemRect(1);
        const center = view.grid.mapToItem(view,
            rect.x + rect.width / 2, rect.y + rect.height / 2);
        dragRootItemWithMouse(0, 1, 0.5, 0.5,
            appGridStyle.dragMergeDelay * 0.6, () => {
                verify(target.mergePending);
                const offset = appGridStyle.dragMergeMoveTolerance + 3;
                mouseMove(view, center.x + offset, center.y, 1, Qt.LeftButton);
                wait(appGridStyle.dragMergeDelay * 0.6);
                verify(target.mergePending);
                verify(!target.mergeArmed,
                    "moving across an icon must restart its dwell");
                tryCompare(target, "mergeArmed", true,
                    appGridStyle.dragMergeDelay + 100);
                mouseMove(view, center.x + offset + 2, center.y + 2,
                    1, Qt.LeftButton);
                verify(target.mergeArmed, "small tremor disarmed the folder");
                mouseMove(view, center.x, center.y, 1, Qt.LeftButton);
                verify(target.mergeArmed);
            });
        compare(controller.rootEntryAt(0).type, "folder");
    }

    function test_unarmedMergeExitMarginRemainsAReorderTarget() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        // 23% is inside the exit margin but outside the 24% entry zone.
        dragRootItemWithMouse(0, 1, 0.23, 0.5,
            appGridStyle.dragReorderDelay + 40, () => {
                verify(view.grid.reorderPreviewActive);
                verify(!findSlot(view.grid, 1).mergePending);
            });
        compare(controller.count, 31);
        compare(controller.rootEntryAt(1).id, "application-0.desktop");
    }

    function test_touchLongPressLiftsThenReordersWithoutLaunching() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const tile = findTile(findSlot(view.grid, 0));
        const source = tile.captureVisual(view).center;
        const rect = view.grid.itemRect(2);
        const target = view.grid.mapToItem(view,
            rect.x + rect.width * 0.08, rect.y + rect.height / 2);
        const touch = touchEvent(view);
        touch.press(0, view, source.x, source.y).commit();
        try {
            tryCompare(tile, "touchDragArmed", true, 800);
            compare(view.grid.dragging, false);
            tryVerify(() => tile.visualScale > 1.05, 400);
            touch.move(0, view, source.x + 35, source.y).commit();
            tryCompare(view.grid, "dragging", true, 300);
            touch.move(0, view, target.x, target.y).commit();
            wait(40);
        } finally {
            touch.release(0, view, target.x, target.y).commit();
        }
        tryCompare(view.grid, "dragging", false, 300);
        wait(0);
        compare(controller.rootEntryAt(2).id, "application-0.desktop");
        compare(applicationLaunchedSpy.count, 0);
        compare(tile.touchDragArmed, false);
    }

    function test_dragUsesStableIdentityAfterCatalogChange() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        dragRootItemWithMouse(0, 3, 0.08, 0.5, 20, source => {
            controller.moveRootItem(0, 1);
            compare(source.safeEntry.id, "application-0.desktop");
        });
        compare(controller.rootEntryAt(3).id, "application-0.desktop");
        compare(controller.count, 31);
        const ids = controller.layoutRows.map(entry => entry.id);
        compare(new Set(ids).size, 31);
    }

    function test_rootMergeCanRemoveTheDragOriginPage_data() {
        return [
            {tag: "ltr-source-page", direction: Qt.LeftToRight, fromLast: true},
            {tag: "rtl-source-page", direction: Qt.RightToLeft, fromLast: true},
            {tag: "ltr-target-page", direction: Qt.LeftToRight, fromLast: false},
            {tag: "rtl-target-page", direction: Qt.RightToLeft, fromLast: false},
        ];
    }

    function test_rootMergeCanRemoveTheDragOriginPage(data) {
        const originalRecords = fakeModel.records;
        try {
            fakeModel.records = originalRecords.slice(0, 25);
            controller.synchronize();
            testCase.visible = true;
            view.layoutDirectionOverride = data.direction;
            wait(0);
            view.playEntrance();
            tryCompare(view, "transitionRunning", false, 800);
            const grid = view.grid;
            compare(grid.pageCount, 2);
            const sourceIndex = data.fromLast ? 24 : 0;
            const targetIndex = data.fromLast ? 0 : 24;
            const targetPage = data.fromLast ? 0 : 1;
            const direction = data.fromLast ? -1 : 1;
            const physicalDirection = grid.rightToLeft ? -direction : direction;
            grid.goToPage(data.fromLast ? 1 : 0, false);
            wait(0);
            const tile = findTile(findSlot(grid, sourceIndex));
            const source = tile.captureVisual(view).center;
            const edge = grid.mapToItem(view,
                physicalDirection > 0 ? grid.width - 4 : 4, grid.height / 2);
            mousePress(view, source.x, source.y, Qt.LeftButton);
            mouseMove(view, source.x + physicalDirection * 40,
                source.y, 20, Qt.LeftButton);
            tryCompare(grid, "dragging", true, 200);
            mouseMove(view, edge.x, edge.y, 20, Qt.LeftButton);
            wait(0);
            const edgeItem = findChild(grid, physicalDirection > 0
                ? "appGridNextEdge" : "appGridPreviousEdge");
            verify(edgeItem.containsDrag);
            compare(grid.edgeDirection, direction);
            tryCompare(grid, "currentPage", targetPage, 1600);
            const rect = grid.itemRect(targetIndex);
            const target = grid.mapToItem(view,
                rect.x + rect.width / 2, rect.y + rect.height / 2);
            mouseMove(view, target.x, target.y, 20, Qt.LeftButton);
            tryCompare(findSlot(grid, targetIndex), "mergeArmed", true, 600);
            mouseRelease(view, target.x, target.y, Qt.LeftButton);
            tryCompare(grid, "dragging", false, 200);
            wait(0);
            compare(controller.count, 24);
            compare(grid.pageCount, 1);
            compare(grid.currentPage, 0);
            const folder = controller.rootEntryAt(data.fromLast ? 0 : 23);
            compare(folder.type, "folder");
            verify(folder.apps.includes(`application-${sourceIndex}.desktop`));
            for (const slot of grid.liveSlots) {
                if (slot.tile) {
                    compare(slot.tile.dragReturnAnimationRunning, false);
                }
            }
            verify(grid.mergeFeedback.running);
            tryCompare(grid.mergeFeedback, "running", false, 700);
            compare(grid.settlingCommittedDrop, false);
            compare(grid.dragOriginIndex, -1);
        } finally {
            mouseRelease(view, 10, 10, Qt.LeftButton);
            view.layoutDirectionOverride = -1;
            fakeModel.records = originalRecords;
            controller.serializedLayout = "";
            controller.synchronize();
            view.reset();
        }
    }

    function test_mouseDragReordersFolderWithoutReturningToOrigin() {
        testCase.visible = true;
        wait(0);
        controller.dropRootItem(0, 1, true);
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        compare(controller.rootEntryAt(0).type, "folder");
        compare(controller.rootEntryAt(2).id, "application-3.desktop");
        const targetSlot = findSlot(view.grid, 2);
        verify(targetSlot);
        const draggedTile = dragRootItemWithMouse(0, 2, 0.08, 0.5);

        compare(controller.count, 30);
        compare(controller.rootEntryAt(2).type, "folder");
        compare(draggedTile.dragReturnAnimationRunning, false);
        compare(draggedTile.dragVisualOffset, Qt.point(0, 0));
        tryCompare(targetSlot, "shiftAnimationRunning", false, 500);
        tryCompare(targetSlot, "renderedShiftOffset", Qt.point(0, 0), 500);
    }

    function test_mouseDragPlacesApplicationBesideFolder() {
        testCase.visible = true;
        wait(0);
        controller.dropRootItem(0, 1, true);
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        compare(controller.rootEntryAt(0).type, "folder");
        compare(controller.rootEntryAt(3).id, "application-4.desktop");

        // The leading edge of the folder is a reorder target, not a merge
        // target, so the application can be inserted before the folder.
        dragRootItemWithMouse(3, 0, 0.08, 0.5);
        compare(controller.rootEntryAt(0).id, "application-4.desktop");
        compare(controller.rootEntryAt(1).type, "folder");
    }

    function test_mouseDragPlacesApplicationBetweenAdjacentFolders() {
        testCase.visible = true;
        wait(0);
        controller.dropRootItem(0, 1, true);
        controller.dropRootItem(1, 2, true);
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        compare(controller.rootEntryAt(0).type, "folder");
        compare(controller.rootEntryAt(1).type, "folder");
        compare(controller.rootEntryAt(3).id, "application-5.desktop");

        dragRootItemWithMouse(3, 1, 0.08, 0.5);
        compare(controller.rootEntryAt(0).type, "folder");
        compare(controller.rootEntryAt(1).id, "application-5.desktop");
        compare(controller.rootEntryAt(2).type, "folder");
    }

    function test_mouseDragCreatesFolder() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        const targetSlot = findSlot(view.grid, 1);
        verify(targetSlot);
        const targetTile = findTile(targetSlot);
        verify(targetTile);
        let observedArmedTarget = false;
        dragRootItemWithMouse(0, 1, 0.5, 0.5,
            appGridStyle.dragMergeDelay + 40, sourceTile => {
                observedArmedTarget = true;
                const sourceLabel = findChild(sourceTile,
                    "appGridApplicationLabel");
                verify(sourceLabel);
                compare(sourceLabel.opacity, 0);
                compare(targetSlot.mergePending, false);
                compare(targetSlot.mergeArmed, true);
                compare(targetTile.dropMergePending, false);
                compare(targetTile.dropMergeArmed, true);
                compare(targetTile.dropHoverActive, true);
                compare(targetTile.dropMergeProgress, 1);
            });

        verify(observedArmedTarget);
        compare(controller.count, 30);
        const folder = controller.rootEntryAt(0);
        compare(folder.type, "folder");
        compare(folder.apps.length, 2);
        compare(folder.apps[0], "application-1.desktop");
        compare(folder.apps[1], "application-0.desktop");
        verify(view.grid.mergeFeedback.running);
        compare(view.grid.mergeFeedback.appId, "application-0.desktop");
        const folderTile = findTile(findSlot(view.grid, 0));
        compare(folderTile.incomingAppId, "application-0.desktop");
        verify(view.grid.mergeFeedback.width
            > view.grid.mergeFeedback.destination.width);
        tryCompare(view.grid.mergeFeedback, "running", false, 700);
        compare(folderTile.incomingAppId, "");
    }

    function test_mouseDragAddsApplicationToFolderAfterDwell() {
        testCase.visible = true;
        wait(0);
        controller.dropRootItem(0, 1, true);
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        const targetSlot = findSlot(view.grid, 0);
        verify(targetSlot);
        compare(targetSlot.entry.type, "folder");
        compare(controller.rootEntryAt(2).id, "application-3.desktop");
        // Existing folders accept a wider central area than app-to-app merge;
        // this point deliberately sits outside the latter's 24% inset.
        dragRootItemWithMouse(2, 0, 0.20, 0.5,
            appGridStyle.dragExistingFolderMergeDelay + 40, () => {
                compare(targetSlot.mergeArmed, true);
            });

        compare(controller.count, 29);
        const folder = controller.rootEntryAt(0);
        compare(folder.type, "folder");
        compare(folder.apps.length, 3);
        compare(folder.apps[2], "application-3.desktop");
        verify(view.grid.mergeFeedback.running);
        compare(view.grid.mergeFeedback.fadeIntoFolder, false);
        tryCompare(view.grid.mergeFeedback, "running", false, 700);
    }

    function test_reducedMotionDropHasNoLandingOrMergeAnimation() {
        testCase.visible = true;
        wait(0);
        appGridStyle.animationsEnabled = false;
        try {
            dragRootItemWithMouse(0, 2, 0.08, 0.5);
            compare(controller.rootEntryAt(2).id, "application-0.desktop");
            for (const slot of view.grid.liveSlots) {
                compare(slot.landingAnimationRunning, false);
                compare(slot.landingX, 0);
                compare(slot.landingY, 0);
            }
            dragRootItemWithMouse(2, 1, 0.5, 0.5,
                appGridStyle.dragMergeDelay + 40);
            compare(controller.rootEntryAt(1).type, "folder");
            compare(view.grid.mergeFeedback.running, false);
            compare(view.grid.mergeFeedback.appId, "");
        } finally {
            appGridStyle.animationsEnabled = true;
        }
    }

    function test_quickCenterDropDoesNotCreateFolderOrReorder() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        const targetSlot = findSlot(view.grid, 1);
        verify(targetSlot);
        const targetTile = findTile(targetSlot);
        verify(targetTile);
        let observedPendingTarget = false;
        const draggedTile = dragRootItemWithMouse(0, 1, 0.5, 0.5,
            20, () => {
                observedPendingTarget = true;
                compare(targetSlot.mergePending, true);
                compare(targetSlot.mergeArmed, false);
                compare(targetTile.dropMergePending, true);
                compare(targetTile.dropMergeArmed, false);
                compare(targetTile.dropHoverActive, true);
            });

        verify(observedPendingTarget);
        compare(controller.count, 31);
        compare(controller.rootEntryAt(0).id, "application-0.desktop");
        compare(controller.rootEntryAt(1).id, "application-1.desktop");
        verify(draggedTile.dragReturnAnimationRunning);
        tryCompare(draggedTile, "dragVisualOffset", Qt.point(0, 0), 500);
    }

    function test_pointerDragIgnoresSmallUnsteadyMovement() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        const sourceRect = view.grid.itemRect(0);
        const sourcePoint = view.grid.mapToItem(view,
            sourceRect.x + sourceRect.width / 2,
            sourceRect.y + sourceRect.height / 2);
        const movement = Math.min(appGridStyle.pointerDragThreshold - 2,
            Qt.styleHints.startDragDistance + 1);
        verify(movement > 0);

        mousePress(view, sourcePoint.x, sourcePoint.y, Qt.LeftButton);
        mouseMove(view, sourcePoint.x + movement, sourcePoint.y,
            20, Qt.LeftButton);
        compare(view.grid.dragging, false);
        mouseRelease(view, sourcePoint.x + movement, sourcePoint.y,
            Qt.LeftButton);

        compare(controller.rootEntryAt(0).id, "application-0.desktop");
        compare(view.grid.dragging, false);
    }

    function test_dragRaisesSourceSlotAndKeepsNeighborPagesClipped() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        const grid = view.grid;
        const originSlot = findSlot(grid, 0);
        verify(originSlot);
        compare(grid.clip, true);
        compare(originSlot.z, 0);
        let observedRaisedSource = false;

        dragRootItemWithMouse(0, 2, 0.08, 0.5, 20,
            sourceTile => {
                observedRaisedSource = true;
                compare(sourceTile.dragging, true);
                compare(originSlot.tileDragging, true);
                compare(originSlot.z, 1000);
                compare(grid.dragging, true);
                compare(grid.clip, true);
            });

        verify(observedRaisedSource);
        compare(grid.dragging, false);
        compare(grid.clip, true);
        compare(originSlot.tileDragging, false);
        compare(originSlot.z, 0);
    }

    function test_reducedMotionDragPreviewIsSynchronous() {
        const grid = view.grid;
        const originSlot = findSlot(grid, 2);
        const shiftedSlot = findSlot(grid, 3);
        verify(originSlot && shiftedSlot);

        appGridStyle.animationsEnabled = false;
        try {
            originSlot.dragStateChanged(true);
            grid.handleSlotDragHover(3, true, false);
            compare(shiftedSlot.renderedShiftOffset, Qt.point(0, 0));
            tryCompare(grid, "reorderPreviewActive", true, 500);
            compare(shiftedSlot.renderedShiftOffset,
                Qt.point(-grid.cellWidth, 0));
            compare(shiftedSlot.shiftAnimationRunning, false);

            grid.handleSlotDragHover(3, false, false);
            originSlot.dragStateChanged(false);
            compare(shiftedSlot.renderedShiftOffset, Qt.point(0, 0));
            compare(shiftedSlot.shiftAnimationRunning, false);
        } finally {
            appGridStyle.animationsEnabled = true;
        }
    }

    function test_cancelledMouseDragStillReturnsToItsOrigin() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        const sourceTile = findTile(findSlot(view.grid, 0));
        verify(sourceTile);
        const sourceRect = view.grid.itemRect(0);
        const sourcePoint = view.grid.mapToItem(view,
            sourceRect.x + sourceRect.width / 2,
            sourceRect.y + sourceRect.height / 2);

        mousePress(view, sourcePoint.x, sourcePoint.y, Qt.LeftButton);
        mouseMove(view, sourcePoint.x + 50, sourcePoint.y,
            20, Qt.LeftButton);
        tryCompare(view.grid, "dragging", true, 200);
        mouseMove(view, 10, 10, 20, Qt.LeftButton);
        mouseRelease(view, 10, 10, Qt.LeftButton);
        tryCompare(view.grid, "dragging", false, 200);
        wait(0);

        compare(controller.rootEntryAt(0).id, "application-0.desktop");
        verify(sourceTile.dragReturnAnimationRunning);
        tryCompare(sourceTile, "dragVisualOffset", Qt.point(0, 0), 500);
        compare(sourceTile.dragReturnAnimationRunning, false);
    }

    function test_folderOpenAndCloseFlow() {
        controller.dropRootItem(0, 1, true);
        const folder = controller.rootEntryAt(0);
        compare(folder.type, "folder");
        view.grid.selectIndex(0);
        const itemRect = view.grid.itemRect(0);
        view.grid.activateSelected();
        tryCompare(view, "activeFolderId", folder.id, 200);
        compare(view.backgroundAccessibilityEnabled, false);
        compare(view.grid.accessibilityEnabled, false);
        verify(Math.abs(view.folderAnimationOrigin.x
            - (view.grid.x + itemRect.x + itemRect.width / 2)) < 1);
        verify(Math.abs(view.folderAnimationOrigin.y
            - (view.grid.y + itemRect.y + itemRect.height / 2)) < 1);
        compare(view.grid.itemCount, 30);

        tryCompare(view, "folderTransitionActive", true, 200);
        verify(view.folderRevealProgress >= 0);
        verify(view.folderRevealProgress < 1);
        tryCompare(view, "folderRevealProgress", 1, 800);
        tryCompare(view, "folderScrimOpacity", 1, 200);
        tryCompare(view, "folderPanelOpacity", 1, 200);
        tryCompare(view, "folderPanelScale", 1, 200);

        view.handleEscape();
        compare(view.activeFolderId, "");
        compare(view.backgroundAccessibilityEnabled, true);
        compare(view.grid.accessibilityEnabled, true);
        verify(view.folderTransitionActive);
        tryCompare(view, "folderRevealProgress", 0, 800);
        tryCompare(view, "folderScrimOpacity", 0, 200);
        tryCompare(view, "folderPanelOpacity", 0, 200);
        verify(!view.folderTransitionActive);
    }

    function test_openFolderBlocksPointerFromBackgroundGrid() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);

        controller.dropRootItem(0, 1, true);
        const folder = controller.rootEntryAt(0);
        view.grid.selectIndex(0);
        view.grid.activateSelected();
        tryCompare(view, "activeFolderId", folder.id, 200);
        wait(appGridStyle.folderDuration + 20);
        compare(view.grid.enabled, false);
        compare(view.grid.selectedIndex, 0);

        // This background cell is geometrically below an empty part of the
        // folder panel. The modal must consume its hover and click without
        // closing the folder or launching the obscured application.
        const coveredRect = view.grid.itemRect(8);
        const coveredPoint = view.grid.mapToItem(view,
            coveredRect.x + coveredRect.width / 2,
            coveredRect.y + coveredRect.height / 2);
        mouseMove(view, coveredPoint.x, coveredPoint.y);
        wait(30);
        compare(view.grid.selectedIndex, 0);

        applicationLaunchedSpy.clear();
        mouseClick(view, coveredPoint.x, coveredPoint.y, Qt.LeftButton);
        wait(30);
        compare(applicationLaunchedSpy.count, 0);
        compare(view.activeFolderId, folder.id);

        // The first column is outside the centered panel but remains below
        // its full-screen scrim. Clicking it closes only the folder.
        const outsideRect = view.grid.itemRect(6);
        const outsidePoint = view.grid.mapToItem(view,
            outsideRect.x + outsideRect.width / 2,
            outsideRect.y + outsideRect.height / 2);
        mouseMove(view, outsidePoint.x, outsidePoint.y);
        mouseClick(view, outsidePoint.x, outsidePoint.y, Qt.LeftButton);
        wait(30);
        compare(applicationLaunchedSpy.count, 0);
        compare(view.activeFolderId, "");
    }

    function test_escapeCancelsFolderRenameBeforeClosingFolder() {
        controller.dropRootItem(0, 1, true);
        const folder = controller.rootEntryAt(0);
        controller.activate("root", 0, "");
        tryCompare(view, "activeFolderId", folder.id, 200);

        view.keyEventProxy.forceActiveFocus(Qt.OtherFocusReason);
        verify(view.keyEventProxy.activeFocus);
        keyClick(Qt.Key_F2);
        tryCompare(view, "folderNameEditing", true, 200);
        view.handleEscape();
        compare(view.folderNameEditing, false);
        compare(view.activeFolderId, folder.id);
        compare(controller.folderName(folder.id), "Folder");

        view.handleEscape();
        compare(view.activeFolderId, "");
    }

    function test_folderRenameReceivesKeyboardInput() {
        controller.dropRootItem(0, 1, true);
        const folder = controller.rootEntryAt(0);
        controller.activate("root", 0, "");
        tryCompare(view, "activeFolderId", folder.id, 200);

        view.keyEventProxy.forceActiveFocus(Qt.OtherFocusReason);
        keyClick(Qt.Key_F2);
        tryCompare(view, "folderNameEditing", true, 200);
        verify(view.folderNameEditor);
        compare(view.keyEventProxy, view.folderNameEditor);

        const renamedFolder = "Renamed Folder";
        for (let index = 0; index < renamedFolder.length; ++index) {
            keyClick(renamedFolder[index]);
        }
        keyClick(Qt.Key_Return);
        tryCompare(view, "folderNameEditing", false, 200);
        compare(controller.folderName(folder.id), renamedFolder);
        compare(view.activeFolderId, folder.id);
    }

    function test_typingSearchClosesAnOpenFolder() {
        controller.dropRootItem(0, 1, true);
        const folder = controller.rootEntryAt(0);
        controller.activate("root", 0, "");
        tryCompare(view, "activeFolderId", folder.id, 200);

        view.searchText = "Application 30";
        compare(view.activeFolderId, "");
        tryCompare(view.grid, "itemCount", 1, 500);
    }

    function test_folderUsesCenteredThreeByThreePages() {
        const members = [];
        for (let index = 0; index < 12; ++index) {
            members.push(`application-${index}.desktop`);
        }
        controller.load(JSON.stringify({
            version: 1,
            items: [{
                type: "folder",
                id: "large-folder",
                name: "Large Folder",
                apps: members,
            }],
        }));

        controller.activate("root", 0, "");
        tryCompare(view, "activeFolderId", "large-folder", 200);
        compare(view.folderGrid.columns, 3);
        compare(view.folderGrid.rows, 3);
        compare(view.folderGrid.pageSize, 9);
        compare(view.folderGrid.pageCount, 2);
        view.folderGrid.goToPage(1, true);
        tryCompare(view.folderGrid, "currentPage", 1, 600);

        view.handleEscape();
        compare(view.activeFolderId, "");
    }

    function test_dragFolderItemAcrossPages() {
        testCase.visible = true;
        const members = [];
        for (let index = 0; index < 12; ++index) {
            members.push(`application-${index}.desktop`);
        }
        controller.load(JSON.stringify({
            version: 1,
            items: [{
                type: "folder",
                id: "drag-pages-folder",
                name: "Drag Pages Folder",
                apps: members,
            }],
        }));
        controller.activate("root", 0, "");
        tryCompare(view, "activeFolderId", "drag-pages-folder", 200);
        tryCompare(view, "folderRevealProgress", 1, 800);

        const grid = view.folderGrid;
        const sourceSlot = findSlot(grid, 0);
        const sourceTile = findTile(sourceSlot);
        verify(sourceSlot && sourceTile);
        const sourcePoint = sourceTile.mapToItem(view,
            sourceTile.width / 2, sourceTile.height / 2);
        const edgePoint = grid.mapToItem(view,
            grid.width - 4, grid.height / 2);

        mousePress(view, sourcePoint.x, sourcePoint.y, Qt.LeftButton);
        mouseMove(view, sourcePoint.x + 50, sourcePoint.y,
            20, Qt.LeftButton);
        tryCompare(grid, "dragging", true, 200);
        mouseMove(view, edgePoint.x, edgePoint.y, 20, Qt.LeftButton);
        const dragCenterBeforePaging = view.mapFromItem(
            null, sourceTile.dragVisualSceneCenter);
        tryCompare(grid, "currentPage", 1, 1400);
        const dragCenterAfterPaging = view.mapFromItem(
            null, sourceTile.dragVisualSceneCenter);
        verify(Math.abs(dragCenterAfterPaging.x
            - dragCenterBeforePaging.x) < 2);
        verify(Math.abs(dragCenterAfterPaging.y
            - dragCenterBeforePaging.y) < 2);

        const targetRect = grid.itemRect(10);
        const targetPoint = grid.mapToItem(view,
            targetRect.x + targetRect.width * 0.08,
            targetRect.y + targetRect.height / 2);
        mouseMove(view, targetPoint.x, targetPoint.y,
            20, Qt.LeftButton);
        wait(40);
        compare(grid.dragHoverIndex, 10);
        mouseRelease(view, targetPoint.x, targetPoint.y, Qt.LeftButton);
        tryCompare(grid, "dragging", false, 200);
        wait(0);

        compare(controller.entryAt("folder", 10,
            "drag-pages-folder").id, "application-0.desktop");
        compare(grid.pageCount, 2);
        compare(grid.currentPage, 1);

        // Exercise the opposite direction too: negative page compensation
        // must keep both the artwork and Drag hot spot under the pointer.
        wait(20);
        const reverseSourceSlot = findSlot(grid, 10);
        const reverseSourceTile = findTile(reverseSourceSlot);
        verify(reverseSourceSlot && reverseSourceTile);
        const reverseSourcePoint = reverseSourceTile.mapToItem(view,
            reverseSourceTile.width / 2, reverseSourceTile.height / 2);
        const previousEdgePoint = grid.mapToItem(view,
            4, grid.height / 2);

        mousePress(view, reverseSourcePoint.x, reverseSourcePoint.y,
            Qt.LeftButton);
        mouseMove(view, reverseSourcePoint.x - 50, reverseSourcePoint.y,
            20, Qt.LeftButton);
        tryCompare(grid, "dragging", true, 200);
        mouseMove(view, previousEdgePoint.x, previousEdgePoint.y,
            20, Qt.LeftButton);
        const reverseCenterBeforePaging = view.mapFromItem(
            null, reverseSourceTile.dragVisualSceneCenter);
        tryCompare(grid, "currentPage", 0, 1400);
        const reverseCenterAfterPaging = view.mapFromItem(
            null, reverseSourceTile.dragVisualSceneCenter);
        verify(Math.abs(reverseCenterAfterPaging.x
            - reverseCenterBeforePaging.x) < 2);
        verify(Math.abs(reverseCenterAfterPaging.y
            - reverseCenterBeforePaging.y) < 2);

        const reverseTargetRect = grid.itemRect(1);
        const reverseTargetPoint = grid.mapToItem(view,
            reverseTargetRect.x + reverseTargetRect.width * 0.08,
            reverseTargetRect.y + reverseTargetRect.height / 2);
        mouseMove(view, reverseTargetPoint.x, reverseTargetPoint.y,
            20, Qt.LeftButton);
        wait(40);
        compare(grid.dragHoverIndex, 1);
        mouseRelease(view, reverseTargetPoint.x, reverseTargetPoint.y,
            Qt.LeftButton);
        tryCompare(grid, "dragging", false, 200);
        wait(0);

        compare(controller.entryAt("folder", 1,
            "drag-pages-folder").id, "application-0.desktop");
        compare(grid.currentPage, 0);

        view.handleEscape();
        compare(view.activeFolderId, "");
        tryCompare(view, "folderTransitionActive", false, 800);
    }

    function test_multiPageDragKeepsItsRenderedIcon_data() {
        return [
            {tag: "root-ltr", folder: false, rtl: false},
            {tag: "root-rtl", folder: false, rtl: true},
            {tag: "folder-ltr", folder: true, rtl: false},
            {tag: "folder-rtl", folder: true, rtl: true},
        ];
    }

    function test_multiPageDragKeepsItsRenderedIcon(data) {
        const originalRecords = fakeModel.records;
        const records = [];
        for (let index = 0; index < 100; ++index) {
            records.push({id: `multi-${index}.desktop`, title: `Multi ${index}`,
                icon: "application-x-executable", description: "Multi-page fixture"});
        }
        try {
            fakeModel.records = records;
            controller.synchronize();
            testCase.visible = true;
            view.layoutDirectionOverride = data.rtl ? Qt.RightToLeft : Qt.LeftToRight;
            view.playEntrance();
            tryCompare(view, "transitionRunning", false, 800);
            if (data.folder) {
                controller.load(JSON.stringify({version: 1, items: [{
                    type: "folder", id: "multi-folder", name: "Multi-page folder",
                    apps: records.slice(0, 40).map(entry => entry.id),
                }]}));
                controller.activate("root", 0, "");
                tryCompare(view, "folderRevealProgress", 1, 800);
            }
            const grid = data.folder ? view.folderGrid : view.grid;
            grid.goToPage(0, false);
            wait(0);
            const source = findTile(findSlot(grid, 0));
            verify(source);
            const start = source.captureVisual(view).center;
            const sign = data.rtl ? -1 : 1;
            mousePress(view, start.x, start.y, Qt.LeftButton);
            mouseMove(view, start.x + sign * 40, start.y, 20, Qt.LeftButton);
            tryCompare(source, "dragging", true, 200);
            const edge = grid.mapToItem(view,
                sign > 0 ? grid.width - 8 : 8, grid.height / 2);
            mouseMove(view, edge.x, edge.y, 20, Qt.LeftButton);
            wait(appGridStyle.tileLiftDuration + 30);
            const initial = source.captureVisual(view).iconRect;
            const reference = renderedIconPixel(source);
            for (let page = 1; page <= 3; ++page) {
                tryCompare(grid, "currentPage", page, 1600);
                verify(source.dragging, `lost pointer grab on page ${page}`);
                compare(source.safeEntry.id, "multi-0.desktop");
                const icon = source.captureVisual(view).iconRect;
                verify(Math.abs(icon.x - initial.x) < 2);
                verify(Math.abs(icon.y - initial.y) < 2);
                compare(renderedIconPixel(source), reference,
                    `drag artwork disappeared on page ${page}`);
                if (page === 2) {
                    grid.synchronizePageGeometry();
                    compare(grid.currentPage, page);
                }
            }
            const reverseEdge = grid.mapToItem(view,
                sign > 0 ? 8 : grid.width - 8, grid.height / 2);
            mouseMove(view, reverseEdge.x, reverseEdge.y, 20, Qt.LeftButton);
            const reverseReference = renderedIconPixel(source);
            for (let page = 2; page >= 1; --page) {
                tryCompare(grid, "currentPage", page, 1600);
                verify(source.dragging);
                compare(renderedIconPixel(source), reverseReference,
                    `drag artwork disappeared returning to page ${page}`);
            }
            const targetIndex = grid.pageSize + 1;
            const cell = grid.itemRect(targetIndex);
            const target = grid.mapToItem(view,
                cell.x + cell.width * 0.08, cell.y + cell.height / 2);
            mouseMove(view, target.x, target.y, 20, Qt.LeftButton);
            mouseRelease(view, target.x, target.y, Qt.LeftButton);
            tryCompare(grid, "dragging", false, 200);
            wait(0);
            compare(controller.entryAt(data.folder ? "folder" : "root",
                targetIndex, data.folder ? "multi-folder" : "").id, "multi-0.desktop");
        } finally {
            mouseRelease(view, 10, 10, Qt.LeftButton);
            if (view.activeFolderId) {
                view.handleEscape();
            }
            view.layoutDirectionOverride = -1;
            fakeModel.records = originalRecords;
            controller.serializedLayout = "";
            controller.synchronize();
            view.reset();
        }
    }

    function renderedIconPixel(tile) {
        const rect = tile.captureVisual(view).iconRect;
        const image = grabImage(view);
        // Sample the inner half facing the viewport, even at a paging edge.
        const x = rect.x + rect.width * (rect.x < view.width / 2 ? 0.65 : 0.35);
        const y = rect.y + rect.height * 0.55;
        return image.pixel(Math.floor(x * image.width / view.width),
            Math.floor(y * image.height / view.height));
    }

    function test_passingThroughAnEdgeDoesNotMoveTheMergeTarget() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const targetSlot = findSlot(view.grid, 2);
        const rect = view.grid.itemRect(2);
        const center = view.grid.mapToItem(view,
            rect.x + rect.width / 2, rect.y + rect.height / 2);
        dragRootItemWithMouse(0, 2, 0.08, 0.5, 100, () => {
            compare(targetSlot.renderedShiftOffset, Qt.point(0, 0),
                "target moved before the pointer could reach its icon");
            mouseMove(view, center.x, center.y, 20, Qt.LeftButton);
            tryCompare(targetSlot, "mergeArmed", true, 600);
            compare(targetSlot.renderedShiftOffset, Qt.point(0, 0));
            return center;
        });
        compare(controller.rootEntryAt(1).type, "folder");
    }

    function test_mergeAcceptsTheOuterPartOfTheIcon_data() {
        return [{tag: "left", x: 0.25}, {tag: "right", x: 0.75}];
    }

    function test_mergeAcceptsTheOuterPartOfTheIcon(data) {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        dragRootItemWithMouse(0, 1, data.x, 0.5,
            appGridStyle.dragMergeDelay + 40, () => {
                verify(findSlot(view.grid, 1).mergeArmed);
                compare(view.grid.reorderPreviewActive, false);
            });
        compare(controller.rootEntryAt(0).type, "folder");
        compare(controller.rootEntryAt(0).apps.join(","),
            "application-1.desktop,application-0.desktop");
    }

    function test_kdeContextMenuIsBuiltLazily() {
        const actions = actionMenu._actionItems();
        compare(actions[0].appGridCommand, "activate");
        compare(actions[2].actionId, "new-window");
        // Launch, separator, KDE jump-list action, separator, Hide.
        compare(actions.length, 5);
        compare(actions[4].appGridCommand, "hide");
        compare(actionMenu.menu.count, 0);
        actionMenu._fillMenu(actionMenu.menu, actions);
        compare(actionMenu.menu.count, 5);
        actionMenu._clearMenu();
        compare(actionMenu.menu.count, 0);
    }

    function test_contextMenuKeepsItsEntryAcrossAsyncModelChanges() {
        const openedEntry = actionMenu.entry;
        compare(openedEntry.id, "application-0.desktop");
        actionMenu.menuEntry = openedEntry;

        controller.moveRootItem(0, 1);
        compare(actionMenu.entry.id, "application-1.desktop");
        actionMenu._dispatch({appGridCommand: "hide"});

        compare(menuHideSpy.count, 1);
        compare(menuHideSpy.signalArguments[0][0],
            "application-0.desktop");
    }

    function findSlot(item, wantedIndex) {
        for (let child = 0; child < item.children.length; ++child) {
            const candidate = item.children[child];
            if (candidate instanceof GridSlot && candidate.globalIndex === wantedIndex) {
                return candidate;
            }
            const nested = findSlot(candidate, wantedIndex);
            if (nested) {
                return nested;
            }
        }
        return null;
    }

    function findTile(item) {
        if (!item) {
            return null;
        }
        for (let child = 0; child < item.children.length; ++child) {
            const candidate = item.children[child];
            if (candidate instanceof AppTile) {
                return candidate;
            }
            const nested = findTile(candidate);
            if (nested) {
                return nested;
            }
        }
        return null;
    }

    function test_runningStateReachesTheVisibleTile() {
        const slot = findSlot(view.grid, 0);
        verify(slot);
        const tile = findTile(slot);
        verify(tile);
        compare(tile.applicationRunning, false);

        controller.runningApplications.runningIds = ({
            "application-0.desktop": true,
        });
        controller.runningApplications.revision += 1;
        tryCompare(tile, "applicationRunning", true, 200);

        controller.runningApplications.runningIds = ({});
        controller.runningApplications.revision += 1;
        tryCompare(tile, "applicationRunning", false, 200);
    }

    function test_dragGapPreviewSlidesTilesAside() {
        const grid = view.grid;
        compare(grid.itemCount, 31);

        const originSlot = findSlot(grid, 2);
        const shiftedSlot = findSlot(grid, 3);
        const wrapSlot = findSlot(grid, 5);
        verify(originSlot && shiftedSlot && wrapSlot);

        originSlot.dragStateChanged(true);
        compare(grid.dragOriginIndex, 2);
        compare(grid.clip, true);
        compare(originSlot.shiftOffset.x, 0);

        // Hovering slot 5 in reorder (edge) mode opens a gap: tiles 3..5
        // slide one cell toward the origin.
        grid.handleSlotDragHover(5, true, false);
        tryCompare(shiftedSlot, "shiftOffset", Qt.point(-grid.cellWidth, 0), 500);
        compare(wrapSlot.shiftOffset.x, -grid.cellWidth);

        // A merge candidate keeps the existing gap frozen so a shifted
        // icon does not escape from underneath the pointer.
        grid.handleSlotDragHover(5, true, true);
        compare(shiftedSlot.shiftOffset, Qt.point(-grid.cellWidth, 0));

        grid.handleSlotDragHover(5, false, false);
        grid.edgeDirection = 1;
        originSlot.dragStateChanged(false);
        compare(grid.clip, true);
        compare(grid.edgeDirection, 0);
        tryCompare(grid, "dragOriginIndex", -1, 100);
        compare(grid.dragHoverIndex, -1);
    }

    function test_dragGapPreviewHoldsFolderTileWhileMergingApp() {
        const grid = view.grid;
        controller.dropRootItem(0, 1, true);
        wait(0);
        compare(grid.itemCount, 30);

        const folderSlot = findSlot(grid, 0);
        const originSlot = findSlot(grid, 2);
        verify(folderSlot && originSlot);
        compare(folderSlot.entry.type, "folder");

        // Hovering the center of a folder with an application keeps the merge
        // target in place; the edge zones still allow reordering beside it.
        originSlot.dragStateChanged(true);
        grid.handleSlotDragHover(0, true, true);
        compare(grid.reorderPreviewActive, false);
        tryCompare(folderSlot, "shiftOffset", Qt.point(0, 0), 200);

        // The leading edge of the same folder opens the reorder gap again, so
        // an application can be placed immediately before the folder.
        grid.handleSlotDragHover(0, true, false);
        tryCompare(grid, "reorderPreviewActive", true, 500);
        tryCompare(folderSlot, "shiftOffset", Qt.point(grid.cellWidth, 0), 200);

        grid.handleSlotDragHover(0, false, false);
        originSlot.dragStateChanged(false);
    }

    function test_openedGapDoesNotMergeWithItsFormerOccupant() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const grid = view.grid;
        const cell = grid.itemRect(3);
        const center = grid.mapToItem(view, cell.x + cell.width / 2, cell.y + cell.height / 2);
        dragRootItemWithMouse(0, 3, 0.08, 0.5,
            appGridStyle.dragReorderDelay + appGridStyle.dragShiftDuration + 60, () => {
                verify(grid.reorderPreviewActive);
                mouseMove(view, center.x, center.y, 20, Qt.LeftButton);
                wait(appGridStyle.dragMergeDelay + 60);
                verify(!grid.mergeArmed && !grid.mergePending, "empty gap armed an invisible merge target");
                compare(grid.reorderPreviewIndex, 3);
                return center;
            });
        compare(controller.count, 31);
        compare(controller.rootEntryAt(3).id, "application-0.desktop");
    }

    function test_mergeFollowsShiftedIconAndKeepsItUnderPointer() {
        testCase.visible = true;
        wait(0);
        view.playEntrance();
        tryCompare(view, "transitionRunning", false, 800);
        const grid = view.grid;
        const cell = grid.itemRect(3);
        const center = grid.mapToItem(view, cell.x + cell.width / 2, cell.y + cell.height / 2);
        const target = findSlot(grid, 4);
        dragRootItemWithMouse(0, 4, 0.08, 0.5,
            appGridStyle.dragReorderDelay + appGridStyle.dragShiftDuration + 60, () => {
                compare(target.renderedShiftOffset, Qt.point(-grid.cellWidth, 0));
                const before = target.captureVisual(grid).center;
                mouseMove(view, center.x, center.y, 20, Qt.LeftButton);
                tryCompare(target, "mergeArmed", true, appGridStyle.dragMergeDelay + 100);
                compare(target.captureVisual(grid).center, before);
                compare(grid.reorderPreviewIndex, 4);
                return center;
            });
        compare(controller.count, 30);
        const folder = controller.rootEntryAt(3);
        compare(folder.type, "folder");
        compare(folder.apps.join(","), "application-4.desktop,application-0.desktop");
    }

    function test_dragGapPreviewWrapsAcrossRows() {
        const grid = view.grid;
        // Column layout: 6 columns. Local index 5 is the row-0 end slot.
        const originSlot = findSlot(grid, 7);
        const rowEndSlot = findSlot(grid, 5);
        verify(originSlot && rowEndSlot);

        originSlot.dragStateChanged(true);
        // Hovering local 5 while dragging local 7 shifts 5..6 toward the
        // higher indices; slot 5 wraps to the next row.
        grid.handleSlotDragHover(5, true, false);
        tryCompare(rowEndSlot, "shiftOffset",
            Qt.point(-grid.cellWidth * (grid.columns - 1), grid.cellHeight), 500);

        originSlot.dragStateChanged(false);
        tryCompare(rowEndSlot, "shiftOffset", Qt.point(0, 0), 500);
    }

    function test_dragGapPreviewContinuesAcrossPages() {
        const grid = view.grid;
        const originSlot = findSlot(grid, 2);
        verify(originSlot);

        originSlot.dragStateChanged(true);
        grid.goToPage(1, false);
        const pageStartSlot = findSlot(grid, grid.pageSize);
        verify(pageStartSlot);

        grid.handleSlotDragHover(grid.pageSize + 2, true, false);
        // A queued geometry update must retain the drag destination even
        // though keyboard selection still belongs to the origin page.
        grid.synchronizePageGeometry();
        compare(grid.currentPage, 1);
        tryCompare(pageStartSlot, "shiftOffset", Qt.point(
            grid.cellWidth * (grid.columns - 1), -grid.cellHeight), 500);

        originSlot.dragStateChanged(false);
        grid.goToPage(0, false);
    }

    function test_dragGapPreviewMirrorsInRightToLeftLayouts() {
        const grid = view.grid;
        view.layoutDirectionOverride = Qt.RightToLeft;
        wait(0);
        verify(view.rightToLeft);
        verify(grid.rightToLeft);
        grid.goToPage(0, false);
        verify(grid._contentXForPage(1) < grid._contentXForPage(0));

        grid.updateTrackpadGesture(grid.width * 0.2);
        grid.settleTrackpadGesture();
        tryCompare(grid, "currentPage", 1, 600);
        compare(grid.selectedIndex, grid.pageSize);
        grid.goToPage(0, false);

        const originSlot = findSlot(grid, 7);
        const wrapSlot = findSlot(grid, 5);
        verify(originSlot && wrapSlot);

        originSlot.dragStateChanged(true);
        grid.handleSlotDragHover(5, true, false);
        tryCompare(wrapSlot, "shiftOffset", Qt.point(
            grid.cellWidth * (grid.columns - 1), grid.cellHeight), 500);
        originSlot.dragStateChanged(false);

        grid.selectIndex(1);
        grid.navigate(Qt.Key_Left, Qt.NoModifier);
        compare(grid.selectedIndex, 2);
        grid.navigate(Qt.Key_Right, Qt.NoModifier);
        compare(grid.selectedIndex, 1);
        compare(grid.edgeDirectionForSide(-1), 1);
        compare(grid.edgeDirectionForSide(1), -1);

        view.layoutDirectionOverride = -1;
        wait(0);
    }

    function test_applicationLaunchUsesGnomeZoomFeedback() {
        const grid = view.grid;
        grid.selectIndex(0);
        const sourceEntry = controller.rootEntryAt(0);
        compare(sourceEntry.type, "app");
        const sourceTile = findTile(findSlot(grid, 0));
        const sourceIcon = findChild(sourceTile, "appGridIconContainer");
        verify(sourceIcon);

        grid.activateSelected();
        verify(view.launchFeedbackRunning);
        verify(view.launchActivationPending);
        verify(view.launchFeedbackOpacity > 0);
        verify(view.launchFeedbackWidth > 0);
        compare(sourceIcon.opacity, 0);
        compare(applicationLaunchedSpy.count, 0);
        const initialScale = view.launchFeedbackScale;

        wait(Math.max(20,
            Math.floor(appGridStyle.appLaunchDuration / 2)));
        verify(view.launchFeedbackScale > initialScale);
        verify(view.launchFeedbackOpacity > 0.99);
        // The process is intentionally not triggered until the feedback is
        // complete, so a fast application window cannot cut it off.
        compare(applicationLaunchedSpy.count, 0);
        tryCompare(view, "launchFeedbackRunning", false, 800);
        compare(applicationLaunchedSpy.count, 1);
        compare(view.launchActivationPending, false);
        compare(view.launchFeedbackOpacity, 0);
        compare(view.pendingLaunchEntry, null);
        compare(sourceIcon.opacity, 0);
        tryCompare(sourceIcon, "opacity", 1, 800);
    }

    function test_runningApplicationActivationSkipsLaunchZoom() {
        const grid = view.grid;
        grid.selectIndex(0);
        controller.runningApplications.runningIds = ({
            "application-0.desktop": true,
        });
        controller.runningApplications.revision += 1;

        grid.activateSelected();
        compare(view.launchFeedbackRunning, false);
        compare(view.launchFeedbackOpacity, 0);
        compare(view.pendingLaunchEntry, null);

        controller.runningApplications.runningIds = ({});
        controller.runningApplications.revision += 1;
    }

    function test_reducedMotionDisablesDurations() {
        appGridStyle.animationsEnabled = false;
        compare(appGridStyle.pageDuration, 0);
        compare(appGridStyle.pageSnapMinimumDuration, 0);
        compare(appGridStyle.entranceDuration, 0);
        compare(appGridStyle.exitDuration, 0);
        compare(appGridStyle.appLaunchDuration, 0);
        compare(appGridStyle.tileMoveDuration, 0);

        appGridStyle.animationsEnabled = true;
        verify(appGridStyle.pageDuration > 0);
        verify(appGridStyle.entranceDuration > 0);
        verify(appGridStyle.exitDuration > 0);
        verify(appGridStyle.appLaunchDuration > 0);
    }

    function test_reducedMotionFolderTransitionIsSynchronous() {
        appGridStyle.animationsEnabled = false;
        try {
            controller.dropRootItem(0, 1, true);
            const folder = controller.rootEntryAt(0);
            view.grid.selectIndex(0);
            view.grid.activateSelected();
            tryCompare(view, "activeFolderId", folder.id, 200);
            wait(0);
            compare(view.folderRevealProgress, 1);

            view.handleEscape();
            wait(0);
            compare(view.folderRevealProgress, 0);
            verify(!view.folderTransitionActive);
            compare(view.folderGrid.folderId, "");
        } finally {
            appGridStyle.animationsEnabled = true;
        }
    }

    function test_partialPageSnapUsesRemainingDistance() {
        const grid = view.grid;
        grid.goToPage(0, false);
        compare(grid.currentPage, 0);

        grid.updateTrackpadGesture(grid.width * 0.75);
        verify(grid.pagePosition > 0.7);
        grid.settleTrackpadGesture();
        verify(grid.pageTransitionRunning);
        verify(grid.activePageAnimationDuration
            >= appGridStyle.pageSnapMinimumDuration);
        verify(grid.activePageAnimationDuration < appGridStyle.pageDuration);
        tryCompare(grid, "currentPage", 1, 600);
        compare(grid.pagePosition, 1);
    }

    function test_manyPagesUseABoundedIndicatorWindow() {
        pageDotsFixture.pageCount = 100;
        pageDotsFixture.currentPosition = 0;
        compare(pageDotsFixture.visibleIndicatorCount, 9);
        compare(pageDotsFixture.firstVisiblePage, 0);

        pageDotsFixture.currentPosition = 50;
        compare(pageDotsFixture.firstVisiblePage, 46);

        pageDotsFixture.currentPosition = 99;
        compare(pageDotsFixture.firstVisiblePage, 91);

        pageDotsFixture.pageCount = 2;
        compare(pageDotsFixture.visibleIndicatorCount, 2);
        compare(pageDotsFixture.firstVisiblePage, 0);
        pageDotsFixture.pageCount = 1;
        pageDotsFixture.currentPosition = 0;
    }

    function test_mouseWheelUsesDiscretePageSteps() {
        const grid = view.grid;
        grid.goToPage(0, false);

        compare(grid.dominantWheelDelta(30, -120), 120);
        compare(grid.dominantWheelDelta(-30, 10), -30);
        compare(grid.wheelEventIsContinuous(
            Qt.NoScrollPhase, 0, -221, 0, -120), false);
        compare(grid.wheelEventIsContinuous(
            Qt.ScrollUpdate, 0, -14, 0, -8), true);
        compare(grid.wheelEventIsContinuous(
            Qt.NoScrollPhase, 0, -14, 0, -8), true);

        verify(grid.handleMouseWheelDelta(120));
        tryCompare(grid, "currentPage", 1, 800);
        compare(grid.selectedIndex, grid.pageSize);

        // The wheel gate consumes a burst as one physical notch/page.
        verify(grid.handleMouseWheelDelta(-120));
        wait(30);
        compare(grid.currentPage, 1);

        wait(180);
        verify(grid.handleMouseWheelDelta(-120));
        tryCompare(grid, "currentPage", 0, 800);
        compare(grid.selectedIndex, 0);
        compare(grid.handleMouseWheelDelta(0), false);
    }
}
