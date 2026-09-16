pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.appgrid.core as Core

Item {
    id: root

    required property AppGridStyle style
    required property LayoutController controller
    property string sourceMode: "root"
    property string folderId: ""
    property int selectedIndex: -1
    property int currentPage: 0
    property real pagePosition: 0
    property int maximumColumns: 6
    property int maximumRows: 4
    property bool adaptiveGridModes: true
    property bool accessibilityEnabled: true
    property string suppressedAppId: ""
    // AppGridView owns application activation so it can finish the short
    // launch acknowledgement before a new window is allowed to cover it.
    // Keep direct controller activation as the standalone/default behavior.
    property bool activationHandledExternally: false
    property var gridModes: [
        {rows: 8, columns: 3},
        {rows: 6, columns: 4},
        {rows: 4, columns: 6},
        {rows: 3, columns: 8},
    ]
    property int layoutDirectionOverride: -1

    readonly property int itemCount: controller.countFor(sourceMode, folderId)
    readonly property int adaptiveModeIndex: _bestAdaptiveModeIndex()
    readonly property int columns: adaptiveModeIndex >= 0
        ? Number(gridModes[adaptiveModeIndex].columns)
        : Math.max(2, Math.min(maximumColumns,
            Math.floor(Math.max(width, style.tileWidth * 2) / style.tileWidth)))
    readonly property int rows: adaptiveModeIndex >= 0
        ? Number(gridModes[adaptiveModeIndex].rows)
        : Math.max(1, Math.min(maximumRows,
            Math.floor(Math.max(height, style.minimumTileHeight)
                / style.minimumTileHeight)))
    readonly property int pageSize: Math.max(1, columns * rows)
    readonly property int pageCount: Math.max(1, Math.ceil(itemCount / pageSize))
    readonly property real cellWidth: Math.min(
        style.tileWidth + style.maximumGridSpacing,
        Math.floor(width / Math.max(1, columns)))
    readonly property real cellHeight: Math.min(
        style.tileHeight + style.maximumGridSpacing,
        Math.floor(height / Math.max(1, rows)))
    readonly property bool dragging: activeDragCount > 0
    readonly property bool pageTransitionRunning: pageAnimation.running
    readonly property int activePageAnimationDuration: pageAnimation.duration
    readonly property alias mergeFeedback: mergeAnimation
    readonly property real pageCacheBuffer: pages.cacheBuffer
    readonly property int liveSlotCount: liveSlots.length
    readonly property bool rightToLeft: layoutDirectionOverride >= 0
        ? layoutDirectionOverride === Qt.RightToLeft
        : Application.layoutDirection === Qt.RightToLeft

    property int activeDragCount: 0
    property GridSlot activeDragSlot: null
    property int dragOriginPage: -1
    property int dragOriginIndex: -1
    property real dragOriginContentX: 0
    property int dragHoverIndex: -1
    property bool dragHoverOverCenter: false
    property int reorderCandidateIndex: -1
    property int reorderPreviewIndex: -1
    property GridSlot mergeTargetSlot: null
    property bool mergePending: false
    property bool mergeArmed: false
    property point mergeAnchor: Qt.point(0, 0)
    property int mergeDwellRevision: 0
    property point lastDragPoint: Qt.point(0, 0)
    property AppTile hoverSource: null
    property bool settlingCommittedDrop: false
    // Register only instantiated slots. Capturing a drop is proportional to
    // the visible page area, even for a catalog with thousands of entries.
    property var liveSlots: []
    property var pendingDrop: null
    property int previewRevision: 0
    property int pendingPage: 0
    property int edgeDirection: 0
    property bool trackpadGestureActive: false
    property int trackpadOriginPage: 0
    property int trackpadDirection: 0

    readonly property bool reorderPreviewActive: {
        root.previewRevision;
        return root.dragging && root.sourceMode !== "search"
            && root.dragOriginIndex >= 0 && root.reorderPreviewIndex >= 0
            && root.reorderPreviewIndex !== root.dragOriginIndex;
    }

    signal itemActivated(int index)
    signal contextMenuRequested(int index)
    signal wheelInputObserved(string source, real delta)

    // Cached neighboring pages must never bleed into the surrounding view.
    // The drag remains visible throughout this item, including its edge-page
    // targets, while naturally disappearing if the pointer leaves the grid.
    clip: true
    // AppGridView mirrors surrounding controls, while this ListView keeps a
    // stable left-to-right coordinate system. In RTL, delegates map physical
    // positions back to reversed logical pages; persisted indexes stay stable
    // while page transitions enter from the expected side.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: false

    ListView {
        id: pages
        objectName: "appGridPages"
        // Ancestor mirroring still reaches children when this Item does not
        // propagate its override, so pin the physical paging surfaces too.
        LayoutMirroring.enabled: false
        anchors.fill: parent
        orientation: ListView.Horizontal
        // Retain one warm neighbor even for zero/one-page searches. Otherwise
        // every broad -> narrow -> broad query destroys and recreates a page
        // of icons during the next render polish.
        model: Core.PageModel { count: Math.max(2, root.pageCount) }
        reuseItems: true
        cacheBuffer: root.dragging
            ? Math.max(0, width * (Math.max(
                Math.abs(root.currentPage - root.dragOriginPage),
                Math.abs(root.pendingPage - root.dragOriginPage)) + 1))
            : Math.max(0, width * 0.35)
        spacing: 0
        interactive: root.enabled && root.pageCount > 1 && !pageAnimation.running && !root.dragging
            && !root.trackpadGestureActive
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2600
        maximumFlickVelocity: width * 3.5
        snapMode: ListView.SnapOneItem
        highlightMoveDuration: 0

        onContentXChanged: {
            if (width <= 0) {
                root.pagePosition = 0;
                return;
            }
            const physicalPosition = Math.max(0, Math.min(
                root.pageCount - 1, (contentX - originX) / width));
            root.pagePosition = root.rightToLeft
                ? root.pageCount - 1 - physicalPosition
                : physicalPosition;
        }

        onMovementEnded: {
            const physicalPage = Math.max(0, Math.min(root.pageCount - 1,
                Math.round((contentX - originX) / Math.max(1, width))));
            const page = root._logicalPageForPhysical(physicalPage);
            root._keepSelectionOnPage(page);
            root.currentPage = page;
            currentIndex = physicalPage;
            positionViewAtIndex(physicalPage, ListView.Beginning);
            root.pagePosition = page;
        }

        delegate: Item {
            id: pageDelegate
            required property int index
            property bool pooled: false
            readonly property int logicalPage: index >= 0 && index < root.pageCount
                ? (root.rightToLeft ? root.pageCount - 1 - index : index) : -1
            readonly property bool reservePage: root.pageCount === 1 && index === 1
            ListView.onPooled: pooled = true
            ListView.onReused: pooled = false
            readonly property int pageItemCount: Math.max(0, Math.min(
                root.pageSize,
                root.itemCount - logicalPage * root.pageSize))
            // Search results form a compact centered row. App folders retain
            // GNOME's fixed 3-column allocation, so an incomplete final row
            // starts at the locale's leading edge.
            readonly property int effectiveColumns: root.sourceMode === "search"
                ? Math.max(1, Math.min(root.columns, pageItemCount))
                : root.columns

            width: pages.width
            height: pages.height
            // Keep return animations above neighboring pages. Active drags
            // render separately in liftedDragLayer, outside the ListView.
            z: root.dragging && logicalPage === root.dragOriginPage ? 1000 : 0

            Item {
                id: pageGrid
                anchors.centerIn: parent
                width: pageDelegate.effectiveColumns * root.cellWidth
                height: root.rows * root.cellHeight

                // Positioners honor LayoutMirroring, so tile order flips for
                // right-to-left locales while page geometry stays untouched.
                LayoutMirroring.enabled:
                    root.rightToLeft
                LayoutMirroring.childrenInherit: true

                Repeater {
                    // Even if a platform creates all lightweight page Items
                    // while the dashboard window is hidden, only the current,
                    // adjacent, and animation-target pages get icon slots.
                    model: {
                        // Read the source values together. Separate derived
                        // logicalPage/reservePage signals can briefly disagree
                        // on a count change, resetting this Repeater twice.
                        const count = root.pageCount;
                        const physical = pageDelegate ? pageDelegate.index : -1;
                        if (!pageDelegate || pageDelegate.pooled || physical < 0
                                || physical >= Math.max(2, count)) {
                            return 0;
                        }
                        const logical = root.rightToLeft ? count - 1 - physical : physical;
                        return count === 1 || Math.abs(logical - root.currentPage) <= 1
                                || logical === root.pendingPage || logical === root.dragOriginPage
                            ? root.pageSize : 0;
                    }

                    delegate: GridSlot {
                        id: slotDelegate
                        required property int index

                        readonly property int absoluteIndex:
                            (pageDelegate ? pageDelegate.logicalPage : 0)
                                * root.pageSize + index

                        width: root.cellWidth
                        height: root.cellHeight
                        x: (root.rightToLeft
                            ? pageDelegate.effectiveColumns - 1 - index % pageDelegate.effectiveColumns
                            : index % pageDelegate.effectiveColumns) * width
                        y: Math.floor(index / pageDelegate.effectiveColumns) * height
                        visible: !pageDelegate.reservePage
                            && (root.sourceMode === "root" || index < pageDelegate.pageItemCount)
                        style: root.style
                        controller: root.controller
                        grid: root
                        sourceMode: root.sourceMode
                        folderId: root.folderId
                        globalIndex: absoluteIndex
                        entry: absoluteIndex >= 0 && absoluteIndex < root.itemCount
                            ? root.controller.entryAt(root.sourceMode, absoluteIndex, root.folderId)
                            : null
                        selected: absoluteIndex === root.selectedIndex
                        accessibleActive: root.accessibilityEnabled && visible
                            && pageDelegate !== null
                            && pageDelegate.logicalPage === root.currentPage
                        suppressedAppId: root.suppressedAppId
                        shiftOffset: root.shiftFor(absoluteIndex)
                        shiftAnimationEnabled: !root.settlingCommittedDrop
                        layoutSettling: root.settlingCommittedDrop
                        incomingAppId: mergeAnimation.appId
                        acceptsDrop: !root.pageTransitionRunning
                            && pageDelegate !== null
                            && pageDelegate.logicalPage === root.currentPage
                        dragPageOffsetX: absoluteIndex === root.dragOriginIndex
                            ? pages.contentX - root.dragOriginContentX : 0
                        dragLayer: liftedDragLayer

                        onActivated: index => {
                            root.selectedIndex = index;
                            root.itemActivated(index);
                            if (!root.activationHandledExternally) {
                                root.controller.activate(
                                    root.sourceMode, index, root.folderId);
                            }
                        }
                        onPointerSelected: index => root.selectedIndex = index
                        onDragStateChanged: active => {
                            if (active && root.pendingDrop) {
                                root.completeDrop();
                            }
                            root.activeDragCount = Math.max(0,
                                root.activeDragCount + (active ? 1 : -1));
                            if (active) {
                                root.activeDragSlot = slotDelegate;
                                mergeAnimation.stop();
                                slotDelegate.clearLanding();
                                root.dragOriginPage = pageDelegate.logicalPage;
                                root.dragOriginIndex = slotDelegate.absoluteIndex;
                                root.dragOriginContentX = pages.contentX;
                                root.previewRevision += 1;
                            } else if (root.activeDragCount === 0) {
                                root.endDrag();
                            }
                        }
                        Component.onCompleted:
                            root.liveSlots = root.liveSlots.concat([slotDelegate])
                        Component.onDestruction: {
                            if (root.activeDragSlot === slotDelegate) {
                                root.endDrag();
                            }
                            root.liveSlots = root.liveSlots.filter(slot => slot !== slotDelegate)
                        }
                        Connections {
                            target: root
                            function onContextMenuRequested(index): void {
                                if (index === slotDelegate.absoluteIndex) {
                                    slotDelegate.openContextMenu();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    MergeAnimation {
        id: mergeAnimation
        style: root.style
    }

    Item {
        id: liftedDragLayer
        anchors.fill: parent
        z: 2000
        LayoutMirroring.enabled: false
    }

    // One arbiter observes a drag. Reorder cells stay fixed, whereas merging
    // follows the icon's rendered position after a gap has opened.
    DropArea {
        id: gridDropArea
        objectName: "appGridDropArea"
        anchors.fill: parent
        z: 100
        keys: ["plasma-appgrid-item"]
        enabled: root.enabled && root.sourceMode !== "search"
        onEntered: drop => root.updateDragHover(drop)
        onPositionChanged: drop => root.updateDragHover(drop)
        onExited: {
            root.hoverSource = null;
            root.resetMergeIntent();
            root.handleSlotDragHover(root.dragHoverIndex, false, false);
        }
        onDropped: drop => root.commitDrag(drop)
    }

    Timer {
        id: mergeArmTimer
        interval: root.mergeTargetSlot !== null && root.mergeTargetSlot.entry !== null
                && root.mergeTargetSlot.entry.type === "folder"
            ? root.style.dragExistingFolderMergeDelay : root.style.dragMergeDelay
        onTriggered: {
            if (gridDropArea.containsDrag && root.mergePending
                    && root.mergeTargetSlot !== null && !root.pageTransitionRunning) {
                root.mergeArmed = true;
                root.mergePending = false;
            }
        }
    }

    NumberAnimation {
        id: pageAnimation
        target: pages
        property: "contentX"
        duration: root.style.pageDuration
        easing.type: Easing.OutCubic
        onFinished: {
            root._keepSelectionOnPage(root.pendingPage);
            root.currentPage = root.pendingPage;
            const physicalPage = root._physicalPageForLogical(root.pendingPage);
            pages.currentIndex = physicalPage;
            pages.positionViewAtIndex(physicalPage, ListView.Beginning);
            root.pagePosition = root.pendingPage;
        }
    }

    Timer {
        id: wheelGate
        interval: 175
    }

    Timer {
        id: trackpadSettleTimer
        interval: 90
        onTriggered: root.settleTrackpadGesture()
    }

    WheelHandler {
        id: wheelHandler

        objectName: "appGridWheelHandler"
        enabled: root.enabled && !root.dragging
        target: null
        // On Linux, Qt documents that touchpads can arrive as ordinary wheel
        // devices. KDE Wayland also represents the seat's pointer as one
        // logical device, so acceptedDevices alone cannot reliably separate a
        // physical wheel from a two-finger gesture. Scroll phases and the
        // angle granularity provide the useful distinction instead.
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const pixelX = Number(event.pixelDelta.x);
            const pixelY = Number(event.pixelDelta.y);
            const angleX = Number(event.angleDelta.x);
            const angleY = Number(event.angleDelta.y);
            const continuous = root.wheelEventIsContinuous(
                event.phase, pixelX, pixelY, angleX, angleY);

            if (continuous) {
                const hasPixelDelta = Math.abs(pixelX) + Math.abs(pixelY) > 0;
                let delta = hasPixelDelta
                    ? root.dominantWheelDelta(pixelX, pixelY)
                    : root.dominantWheelDelta(angleX, angleY)
                        / 120 * root.width * 0.18;
                if (Math.abs(delta) >= 0.01) {
                    root.wheelInputObserved("touchpad", delta);
                    root.updateTrackpadGesture(delta);
                }
                if (event.phase === Qt.ScrollEnd) {
                    trackpadSettleTimer.stop();
                    Qt.callLater(() => root.settleTrackpadGesture());
                }
                event.accepted = event.phase !== Qt.NoScrollPhase
                    || Math.abs(delta) >= 0.01;
                return;
            }

            // Prefer the standardized angle delta for a conventional wheel.
            // Wayland may also provide a scaled pixel delta for the very same
            // notch; using it would misclassify one notch as a long gesture.
            const angleDelta = root.dominantWheelDelta(angleX, angleY);
            const delta = Math.abs(angleDelta) >= 0.01
                ? angleDelta : root.dominantWheelDelta(pixelX, pixelY);
            if (Math.abs(delta) >= 0.01) {
                root.wheelInputObserved("mouse", delta);
            }
            event.accepted = root.handleMouseWheelDelta(delta);
        }
    }

    PinchHandler {
        id: pinchHandler
        enabled: root.enabled && !root.dragging
        target: pages
        minimumScale: 0.84
        maximumScale: 1.08
        xAxis.enabled: false
        yAxis.enabled: false
        rotationAxis.enabled: false
        onActiveChanged: {
            if (!active) {
                scaleReset.restart();
            }
        }
    }

    NumberAnimation {
        id: scaleReset
        target: pages
        property: "scale"
        to: 1
        duration: root.style.tileReleaseDuration
        easing.type: Easing.OutCubic
    }

    DropArea {
        id: previousEdge
        objectName: "appGridPreviousEdge"
        LayoutMirroring.enabled: false
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(28, parent.width * 0.11)
        keys: ["plasma-appgrid-item"]
        enabled: root.dragging && (root.rightToLeft
            ? root.currentPage < root.pageCount - 1
            : root.currentPage > 0)
        z: 500

        onEntered: {
            root.edgeDirection = root.edgeDirectionForSide(-1);
            edgeTimer.restart();
        }
        onExited: {
            if (root.edgeDirection === root.edgeDirectionForSide(-1)) {
                edgeTimer.stop();
                root.edgeDirection = 0;
            }
        }

        Rectangle {
            anchors.fill: parent
            opacity: previousEdge.containsDrag ? 1 : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.style.edgeGlow }
                GradientStop { position: 1; color: "transparent" }
            }

            Behavior on opacity { NumberAnimation { duration: root.style.tileFeedbackDuration } }
        }
    }

    DropArea {
        id: nextEdge
        objectName: "appGridNextEdge"
        LayoutMirroring.enabled: false
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(28, parent.width * 0.11)
        keys: ["plasma-appgrid-item"]
        enabled: root.dragging && (root.rightToLeft
            ? root.currentPage > 0
            : root.currentPage < root.pageCount - 1)
        z: 500

        onEntered: {
            root.edgeDirection = root.edgeDirectionForSide(1);
            edgeTimer.restart();
        }
        onExited: {
            if (root.edgeDirection === root.edgeDirectionForSide(1)) {
                edgeTimer.stop();
                root.edgeDirection = 0;
            }
        }

        Rectangle {
            anchors.fill: parent
            opacity: nextEdge.containsDrag ? 1 : 0
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: root.style.edgeGlow }
            }

            Behavior on opacity { NumberAnimation { duration: root.style.tileFeedbackDuration } }
        }
    }

    Timer {
        id: edgeTimer
        interval: Math.max(root.style.dragEdgeDelay, root.style.pageDuration + 80)
        repeat: true
        onTriggered: root.advanceDragEdgePage()
    }

    function prepareDrop(source, sourceIndex, targetIndex, merge): void {
        mergeAnimation.stop();
        const positions = Object.create(null);
        for (const slot of liveSlots) {
            const snapshot = slot.captureVisual(root);
            if (snapshot) {
                positions[snapshot.entry.id] = snapshot;
            }
        }
        const target = controller.entryAt(sourceMode,
            Math.min(targetIndex, itemCount - 1), folderId);
        pendingDrop = {
            positions,
            source: source.captureVisual(root),
            targetId: target ? target.id : "",
            destinationIndex: merge
                ? targetIndex - (sourceIndex < targetIndex ? 1 : 0)
                : Math.min(targetIndex, itemCount - 1),
            merge,
        };
        // Freeze before the model changes, then apply identity-matched
        // offsets in the same event-loop turn, before the next painted frame.
        settlingCommittedDrop = true;
        selectedIndex = pendingDrop.destinationIndex;
        // Merging the only item on the last page can destroy the source
        // inside Drag.drop(). Completion belongs to the grid, never to a
        // signal emitted by that source after the model mutation returns.
        Qt.callLater(root.completeDrop);
    }

    function completeDrop(): void {
        const drop = pendingDrop;
        if (!drop) {
            return;
        }
        pendingDrop = null;
        endDrag();
        selectedIndex = Math.max(0, Math.min(itemCount - 1, drop.destinationIndex));
        // In RTL removing a page also shifts every physical page position.
        // Resolve that geometry before calculating the landing offsets.
        goToPage(Math.floor(selectedIndex / pageSize), false);
        const destination = controller.entryAt(sourceMode,
            drop.destinationIndex, folderId);
        if (drop.merge && destination) {
            // A newly created folder inherits the target app's rendered
            // position, while the incoming app flies into its own miniature.
            drop.positions[destination.id] = drop.positions[drop.targetId];
        }
        for (const slot of liveSlots) {
            slot.settleFrom(slot.entry ? drop.positions[slot.entry.id] : null, root);
        }
        if (drop.merge && destination && destination.type === "folder") {
            const memberIndex = destination.apps.indexOf(drop.source.entry.id);
            const icon = iconRect(drop.destinationIndex);
            const miniature = style.folderPreviewRect(icon.width,
                Math.max(0, Math.min(memberIndex, 3)), rightToLeft);
            mergeAnimation.start(drop.source.entry, drop.source.iconRect,
                Qt.rect(icon.x + miniature.x, icon.y + miniature.y,
                    miniature.width, miniature.height), memberIndex >= 4);
        }
        settlingCommittedDrop = false;
    }

    function endDrag(): void {
        activeDragCount = 0;
        activeDragSlot = null;
        hoverSource = null;
        resetMergeIntent();
        edgeTimer.stop();
        edgeDirection = 0;
        dragHoverIndex = -1;
        dragHoverOverCenter = false;
        clearReorderPreview();
        previewRevision += 1;
        _keepSelectionOnPage(currentPage);
        // Retain page compensation through a synchronous Drag.drop().
        Qt.callLater(() => {
            if (!root.dragging) {
                root.dragOriginPage = -1;
                root.dragOriginIndex = -1;
                root.dragOriginContentX = pages.contentX;
                root.previewRevision += 1;
            }
        });
    }

    function iconRect(index): rect {
        const cell = itemRect(index);
        const tileWidth = Math.min(style.tileWidth, cell.width);
        const tileHeight = Math.min(style.tileHeight, cell.height);
        const size = Math.max(0, Math.min(style.iconSize,
            tileWidth - 24, tileHeight - style.tileTextReserve));
        return Qt.rect(cell.x + (cell.width - size) / 2,
            cell.y + (cell.height - tileHeight) / 2 + style.tileTopPadding,
            size, size);
    }

    onPageCountChanged: {
        // In RTL every physical index shifts when the page count changes,
        // including when the current logical page remains zero.
        Qt.callLater(root.synchronizePageGeometry);
    }

    onPageSizeChanged: Qt.callLater(root.synchronizePageGeometry)

    function handleSlotDragHover(index, active, overCenter): void {
        if (active) {
            if (dragHoverIndex === index && dragHoverOverCenter === overCenter) {
                return;
            }
            dragHoverIndex = index;
            dragHoverOverCenter = overCenter;
            hoverExitTimer.stop();
            if (overCenter) {
                // Preserve the current gap: closing it would pull a shifted
                // merge target away from the pointer that just reached it.
                reorderIntentTimer.stop();
                reorderCandidateIndex = -1;
            } else if (index === dragOriginIndex) {
                clearReorderPreview();
            } else {
                reorderCandidateIndex = index;
                reorderIntentTimer.restart();
            }
        } else if (dragHoverIndex === index) {
            dragHoverIndex = -1;
            dragHoverOverCenter = false;
            reorderIntentTimer.stop();
            reorderCandidateIndex = -1;
            // Adjacent DropAreas emit exit and enter separately. Keep the
            // existing gap through that boundary instead of flashing it shut.
            hoverExitTimer.restart();
        } else {
            return;
        }
        previewRevision += 1;
    }

    function clearReorderPreview(): void {
        reorderIntentTimer.stop();
        hoverExitTimer.stop();
        reorderCandidateIndex = -1;
        reorderPreviewIndex = -1;
    }

    Timer {
        id: reorderIntentTimer
        interval: root.style.dragReorderDelay
        onTriggered: {
            if (root.dragging && !root.dragHoverOverCenter
                    && root.dragHoverIndex === root.reorderCandidateIndex) {
                root.reorderPreviewIndex = root.reorderCandidateIndex;
                root.previewRevision += 1;
                root.resetMergeIntent();
            }
        }
    }

    function resetMergeIntent(): void {
        mergeArmTimer.stop();
        mergePending = false;
        mergeArmed = false;
        mergeTargetSlot = null;
    }

    function cellIndexAt(point): int {
        const first = itemRect(currentPage * pageSize);
        const left = rightToLeft ? first.x - (columns - 1) * cellWidth : first.x;
        const column = Math.floor((point.x - left) / cellWidth);
        const row = Math.floor((point.y - first.y) / cellHeight);
        if (column < 0 || column >= columns || row < 0 || row >= rows) {
            return -1;
        }
        return currentPage * pageSize + row * columns
            + (rightToLeft ? columns - 1 - column : column);
    }

    function insideMergeZone(slot, point, exiting): bool {
        const icon = iconRect(slot.globalIndex);
        const shift = slot.renderedShiftOffset;
        const folder = slot.entry.type === "folder";
        const halfWidth = icon.width * (folder ? 0.62 : 0.5)
            + (exiting ? icon.width * 0.12 : 0);
        const halfHeight = icon.height * (folder ? 0.66 : 0.55)
            + (exiting ? icon.height * 0.12 : 0);
        return Math.abs(point.x - icon.x - shift.x - icon.width / 2) < halfWidth
            && Math.abs(point.y - icon.y - shift.y - icon.height / 2) < halfHeight;
    }

    function mergeSlotAt(point, source): GridSlot {
        if (!source || sourceMode !== "root" || source.sourceMode !== "root"
                || source.safeEntry.type !== "app") {
            return null;
        }
        if (mergeTargetSlot !== null && mergeTargetSlot.entry !== null
                && mergeTargetSlot.entry.id !== source.safeEntry.id
                && insideMergeZone(mergeTargetSlot, point, true)) {
            return mergeTargetSlot;
        }
        for (const slot of liveSlots) {
            if (slot.entry === null || slot.entry.id === source.safeEntry.id
                    || !slot.acceptsDrop || slot.shiftAnimationRunning
                    || slot.landingAnimationRunning) {
                continue;
            }
            if (insideMergeZone(slot, point, false)) {
                return slot;
            }
        }
        return null;
    }

    function updateDragHover(drop): void {
        hoverSource = drop.source as AppTile;
        lastDragPoint = Qt.point(drop.x, drop.y);
        refreshDragHover();
    }

    function refreshDragHover(): void {
        if (!hoverSource || !dragging) {
            return;
        }
        if (pageTransitionRunning) {
            resetMergeIntent();
            clearReorderPreview();
            return;
        }
        const index = cellIndexAt(lastDragPoint);
        const candidate = index >= 0 ? mergeSlotAt(lastDragPoint, hoverSource) : null;
        if (candidate !== mergeTargetSlot) {
            resetMergeIntent();
            if (candidate !== null) {
                mergeTargetSlot = candidate;
                mergeAnchor = lastDragPoint;
                mergePending = true;
                mergeArmTimer.restart();
            }
        } else if (mergePending && Math.hypot(lastDragPoint.x - mergeAnchor.x,
                lastDragPoint.y - mergeAnchor.y) > style.dragMergeMoveTolerance) {
            mergeAnchor = lastDragPoint;
            mergeDwellRevision += 1;
            mergeArmTimer.restart();
        }
        if (index >= 0) {
            handleSlotDragHover(index, true, candidate !== null);
        } else {
            handleSlotDragHover(dragHoverIndex, false, false);
        }
    }

    onPageTransitionRunningChanged: {
        if (pageTransitionRunning) {
            resetMergeIntent();
            clearReorderPreview();
        } else if (dragging) {
            Qt.callLater(root.refreshDragHover);
        }
    }

    function commitDrag(drop): void {
        const source = drop.source as AppTile;
        if (!source || pageTransitionRunning) {
            resetMergeIntent();
            return;
        }
        updateDragHover(drop);
        const sourceIndex = controller.indexOfEntry(source.sourceMode,
            source.safeEntry.id, source.sourceFolderId);
        const sameGrid = source.sourceMode === sourceMode
            && (sourceMode !== "folder" || source.sourceFolderId === folderId);
        const merge = mergeTargetSlot !== null && mergeArmed;
        const targetIndex = merge ? mergeTargetSlot.globalIndex : cellIndexAt(lastDragPoint);
        // A quick center release returns home; only the visible armed halo
        // promises a folder. Releasing in the opened gap always reorders.
        if (!sameGrid || sourceIndex < 0 || targetIndex < 0
                || sourceIndex === targetIndex || (mergePending && !merge)) {
            resetMergeIntent();
            return;
        }
        prepareDrop(source, sourceIndex, targetIndex, merge);
        drop.accept(Qt.MoveAction);
        if (sourceMode === "root") {
            controller.dropRootItem(sourceIndex, targetIndex, merge);
        } else if (sourceMode === "folder") {
            controller.reorderFolder(folderId, sourceIndex, targetIndex);
        }
        resetMergeIntent();
    }

    Timer {
        id: hoverExitTimer
        interval: root.style.dragHoverExitDelay
        onTriggered: {
            if (root.dragHoverIndex < 0) {
                root.clearReorderPreview();
            }
        }
    }

    function edgeDirectionForSide(physicalSide): int {
        const side = physicalSide < 0 ? -1 : 1;
        return rightToLeft ? -side : side;
    }

    function advanceDragEdgePage(): void {
        if (pageAnimation.running) {
            return;
        }
        const targetPage = Math.max(0, Math.min(
            pageCount - 1, currentPage + edgeDirection));
        if (targetPage === currentPage) {
            edgeTimer.stop();
            return;
        }
        // Keep the repeating timer alive while the pointer remains at the
        // edge, allowing a drag to cross more than one page.
        goToPage(targetPage, true, true);
    }

    // GNOME Shell opens a visual gap at the hovered slot while dragging by
    // sliding the icons between the origin and the hover position by one cell.
    // The same absolute-index calculation also works after edge switching:
    // items at a page boundary slide out toward the neighboring page while a
    // gap opens on the destination page.
    function shiftFor(absoluteIndex): point {
        root.previewRevision;
        if (!reorderPreviewActive) {
            return Qt.point(0, 0);
        }

        const pageStart = root.currentPage * root.pageSize;
        const hoverLocal = root.reorderPreviewIndex - pageStart;
        const local = absoluteIndex - pageStart;
        if (hoverLocal < 0 || hoverLocal >= root.pageSize
                || local < 0 || local >= root.pageSize
                || absoluteIndex === root.dragOriginIndex) {
            return Qt.point(0, 0);
        }

        let direction = 0;
        if (root.dragOriginIndex < root.reorderPreviewIndex) {
            if (absoluteIndex > root.dragOriginIndex
                    && absoluteIndex <= root.reorderPreviewIndex) {
                direction = -1;
            }
        } else if (absoluteIndex >= root.reorderPreviewIndex
                && absoluteIndex < root.dragOriginIndex) {
            direction = 1;
        }
        if (direction === 0) {
            return Qt.point(0, 0);
        }

        const columnCount = Math.max(1, root.columns);
        const column = local % columnCount;
        const horizontalSign = root.rightToLeft ? -1 : 1;
        if (direction < 0) {
            return column > 0
                ? Qt.point(-root.cellWidth * horizontalSign, 0)
                : Qt.point(root.cellWidth * (columnCount - 1)
                    * horizontalSign, -root.cellHeight);
        }
        return column < columnCount - 1
            ? Qt.point(root.cellWidth * horizontalSign, 0)
            : Qt.point(-root.cellWidth * (columnCount - 1)
                * horizontalSign, root.cellHeight);
    }

    onItemCountChanged: {
        if (itemCount === 0) {
            selectedIndex = -1;
        } else if (selectedIndex < 0) {
            selectedIndex = 0;
        } else if (selectedIndex >= itemCount) {
            selectedIndex = itemCount - 1;
        }
    }

    onWidthChanged: Qt.callLater(root.synchronizePageGeometry)
    onRightToLeftChanged: Qt.callLater(() => goToPage(currentPage, false))

    function _bestAdaptiveModeIndex(): int {
        if (!adaptiveGridModes || !gridModes || gridModes.length === 0
                || width <= 0 || height <= 0) {
            return -1;
        }

        const sizeRatio = width / height;
        let closestDistance = Number.POSITIVE_INFINITY;
        let bestIndex = -1;
        for (let index = 0; index < gridModes.length; ++index) {
            const mode = gridModes[index];
            const modeColumns = Number(mode.columns ?? 0);
            const modeRows = Number(mode.rows ?? 0);
            if (modeColumns < 1 || modeRows < 1
                    || modeColumns * style.tileWidth > width
                    || modeRows * style.minimumTileHeight > height) {
                continue;
            }
            const distance = Math.abs(sizeRatio - modeColumns / modeRows);
            if (distance < closestDistance) {
                closestDistance = distance;
                bestIndex = index;
            }
        }
        return bestIndex;
    }

    function synchronizePageGeometry(): void {
        // Selection remains at the drag origin until release. A queued
        // resize or catalog update must not send an edge drag back there.
        const targetPage = dragging ? pendingPage
            : (selectedIndex >= 0
                ? Math.floor(selectedIndex / pageSize) : currentPage);
        goToPage(targetPage, false, dragging);
    }

    function updateTrackpadGesture(delta): void {
        if (!isFinite(delta) || Math.abs(delta) < 0.01 || pages.width <= 0) {
            return;
        }
        if (!trackpadGestureActive) {
            pageAnimation.stop();
            trackpadGestureActive = true;
            trackpadOriginPage = currentPage;
            trackpadDirection = 0;
        }

        trackpadDirection = delta > 0 ? 1 : -1;
        const originX = _contentXForPage(trackpadOriginPage);
        const minimumX = Math.max(pages.originX, originX - pages.width);
        const maximumX = Math.min(
            pages.originX + (pageCount - 1) * pages.width, originX + pages.width);
        const physicalDelta = rightToLeft ? -delta : delta;
        pages.contentX = Math.max(minimumX, Math.min(
            maximumX, pages.contentX + physicalDelta));
        trackpadSettleTimer.restart();
    }

    function dominantWheelDelta(horizontal, vertical): real {
        const x = Number(horizontal);
        const y = Number(vertical);
        if (!isFinite(x) || !isFinite(y)) {
            return 0;
        }
        return Math.abs(x) > Math.abs(y) ? x : -y;
    }

    function wheelEventIsContinuous(phase, pixelX, pixelY,
                                    angleX, angleY): bool {
        if (phase !== Qt.NoScrollPhase) {
            return true;
        }

        const angleDelta = Math.abs(dominantWheelDelta(angleX, angleY));
        const pixelDelta = Math.abs(dominantWheelDelta(pixelX, pixelY));
        if (angleDelta < 0.01) {
            return pixelDelta >= 0.01;
        }

        // A click wheel reports whole 120-unit steps. Partial angle steps are
        // high-resolution input and should retain continuous paging even on a
        // backend that cannot provide ScrollBegin/Update/End phases.
        const remainder = angleDelta % 120;
        return remainder > 0.01 && 120 - remainder > 0.01;
    }

    function handleMouseWheelDelta(delta): bool {
        if (!isFinite(delta) || Math.abs(delta) < 1) {
            return false;
        }
        if (!wheelGate.running) {
            goToPage(currentPage + (delta > 0 ? 1 : -1), true);
            wheelGate.restart();
        }
        return true;
    }

    function settleTrackpadGesture(): void {
        if (!trackpadGestureActive || pages.width <= 0) {
            return;
        }
        trackpadSettleTimer.stop();
        const physicalDisplacement = (pages.contentX
            - _contentXForPage(trackpadOriginPage)) / pages.width;
        const displacement = rightToLeft
            ? -physicalDisplacement : physicalDisplacement;
        let targetPage = trackpadOriginPage;
        if (Math.abs(displacement) >= 0.08) {
            targetPage += displacement > 0 ? 1 : -1;
        }
        trackpadGestureActive = false;
        trackpadDirection = 0;
        goToPage(targetPage, true);
    }

    function goToPage(page, animated, preserveEdgePaging): void {
        pages.forceLayout();
        const targetPage = Math.max(0, Math.min(pageCount - 1, page));
        const targetX = _contentXForPage(targetPage);
        _keepSelectionOnPage(targetPage);
        if (!preserveEdgePaging) {
            edgeTimer.stop();
        }
        trackpadSettleTimer.stop();
        trackpadGestureActive = false;
        trackpadDirection = 0;
        // Stop an in-flight transition even when this request appears to be a
        // no-op. Otherwise its next frame can move the ListView to the stale
        // destination after reset(), an RTL flip, or a reversed edge drag.
        pendingPage = targetPage;
        pageAnimation.stop();
        pages.cancelFlick();
        if (targetPage === currentPage
                && Math.abs(pages.contentX - targetX) < 1) {
            const physicalPage = _physicalPageForLogical(targetPage);
            pages.currentIndex = physicalPage;
            pages.positionViewAtIndex(physicalPage, ListView.Beginning);
            pages.contentX = _contentXForPage(targetPage);
            pagePosition = targetPage;
            return;
        }

        if (!animated || pages.width <= 0) {
            currentPage = targetPage;
            const physicalPage = _physicalPageForLogical(targetPage);
            pages.currentIndex = physicalPage;
            pages.positionViewAtIndex(physicalPage, ListView.Beginning);
            pages.contentX = _contentXForPage(targetPage);
            pagePosition = targetPage;
            return;
        }

        pageAnimation.from = pages.contentX;
        pageAnimation.to = targetX;
        pageAnimation.duration = style.pageTransitionDuration(
            Math.abs(targetX - pages.contentX) / Math.max(1, pages.width));
        pageAnimation.restart();
    }

    function _physicalPageForLogical(logicalPage): int {
        const boundedPage = Math.max(0, Math.min(
            pageCount - 1, Number(logicalPage)));
        return rightToLeft ? pageCount - 1 - boundedPage : boundedPage;
    }

    function _logicalPageForPhysical(physicalPage): int {
        const boundedPage = Math.max(0, Math.min(
            pageCount - 1, Number(physicalPage)));
        return rightToLeft ? pageCount - 1 - boundedPage : boundedPage;
    }

    function _contentXForPage(logicalPage): real {
        return pages.originX + _physicalPageForLogical(logicalPage) * pages.width;
    }

    function _keepSelectionOnPage(page): void {
        if (dragging || itemCount === 0) {
            return;
        }
        const firstIndex = Math.max(0, Math.min(
            itemCount - 1, page * pageSize));
        const lastIndex = Math.min(
            itemCount - 1, firstIndex + pageSize - 1);
        if (selectedIndex < firstIndex || selectedIndex > lastIndex) {
            selectedIndex = firstIndex;
        }
    }

    function selectIndex(index): void {
        if (itemCount === 0) {
            selectedIndex = -1;
            return;
        }
        selectedIndex = Math.max(0, Math.min(itemCount - 1, index));
        goToPage(Math.floor(selectedIndex / pageSize), true);
    }

    function navigate(key, modifiers): void {
        if (itemCount === 0) {
            selectedIndex = -1;
            return;
        }
        const rightToLeft = root.rightToLeft;
        let target = selectedIndex < 0 ? 0 : selectedIndex;
        switch (key) {
        case Qt.Key_Left:
            target += rightToLeft ? 1 : -1;
            break;
        case Qt.Key_Right:
            target += rightToLeft ? -1 : 1;
            break;
        case Qt.Key_Up:
            target -= columns;
            break;
        case Qt.Key_Down:
            target += columns;
            break;
        case Qt.Key_PageUp:
            target -= pageSize;
            break;
        case Qt.Key_PageDown:
            target += pageSize;
            break;
        case Qt.Key_Home:
            target = (modifiers & Qt.ControlModifier)
                ? 0 : Math.floor(target / pageSize) * pageSize;
            break;
        case Qt.Key_End:
            target = (modifiers & Qt.ControlModifier)
                ? itemCount - 1
                : Math.min(itemCount - 1,
                    (Math.floor(target / pageSize) + 1) * pageSize - 1);
            break;
        }
        selectIndex(target);
    }

    function activateSelected(): void {
        if (selectedIndex < 0 && itemCount > 0) {
            selectedIndex = 0;
        }
        if (selectedIndex >= 0) {
            itemActivated(selectedIndex);
            if (!activationHandledExternally) {
                controller.activate(sourceMode, selectedIndex, folderId);
            }
        }
    }

    function openSelectedContextMenu(): void {
        if (selectedIndex < 0 && itemCount > 0) {
            selectedIndex = 0;
        }
        if (selectedIndex >= 0) {
            contextMenuRequested(selectedIndex);
        }
    }

    function itemRect(index): rect {
        if (index < 0 || index >= itemCount) {
            return Qt.rect(0, 0, 0, 0);
        }
        const itemPage = Math.floor(index / pageSize);
        const physicalPage = _physicalPageForLogical(itemPage);
        const localIndex = index % pageSize;
        const pageItemCount = Math.max(0, Math.min(
            pageSize, itemCount - itemPage * pageSize));
        const effectiveColumns = sourceMode === "search"
            ? Math.max(1, Math.min(columns, pageItemCount)) : columns;
        const column = localIndex % effectiveColumns;
        const row = Math.floor(localIndex / effectiveColumns);
        const visualColumn = rightToLeft
            ? effectiveColumns - column - 1 : column;
        const gridWidth = effectiveColumns * cellWidth;
        const gridHeight = rows * cellHeight;
        return Qt.rect(
            (width - gridWidth) / 2 + visualColumn * cellWidth
                + pages.originX + physicalPage * width - pages.contentX,
            (height - gridHeight) / 2 + row * cellHeight,
            cellWidth,
            cellHeight);
    }

    function reset(): void {
        endDrag();
        pendingDrop = null;
        mergeAnimation.stop();
        settlingCommittedDrop = false;
        for (const slot of liveSlots) {
            slot.clearLanding();
        }
        selectedIndex = itemCount > 0 ? 0 : -1;
        goToPage(0, false);
    }

    function resetSearchPosition(): void {
        // Search cannot drag. Avoid walking every slot and invalidating drag
        // bindings on each keystroke; reset those only when a drag is active.
        if (dragging || pendingDrop || mergeAnimation.running) {
            reset();
            return;
        }
        selectedIndex = itemCount > 0 ? 0 : -1;
        if (currentPage !== 0 || pendingPage !== 0 || pageAnimation.running
                || trackpadGestureActive || pages.moving
                || Math.abs(pages.contentX - _contentXForPage(0)) >= 1) {
            goToPage(0, false);
        }
    }
}
