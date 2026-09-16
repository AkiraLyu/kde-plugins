pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property AppGridStyle style
    required property LayoutController controller
    required property string sourceMode
    required property int globalIndex
    required property var entry
    property var displayEntry: null
    property PagedGrid grid: null
    property string folderId: ""
    property bool selected: false
    property bool accessibleActive: true
    property string suppressedAppId: ""
    property point shiftOffset: Qt.point(0, 0)
    property real dragPageOffsetX: 0
    property Item dragLayer: null
    property bool shiftAnimationEnabled: true
    property bool layoutSettling: false
    property bool acceptsDrop: true
    property string incomingAppId: ""
    property real landingX: 0
    property real landingY: 0
    property real landingScale: 1
    property bool landingDragged: false
    readonly property bool landingAnimationRunning: landingAnimation.running
    readonly property point renderedShiftOffset:
        Qt.point(slotShift.x, slotShift.y)
    readonly property bool shiftAnimationRunning:
        Math.abs(slotShift.x - shiftOffset.x) > 0.25
            || Math.abs(slotShift.y - shiftOffset.y) > 0.25
    readonly property bool mergePending: grid !== null && grid.mergeTargetSlot === root && grid.mergePending
    readonly property bool mergeArmed: grid !== null && grid.mergeTargetSlot === root && grid.mergeArmed
    readonly property bool dropHoverActive: grid !== null
        && (grid.dragHoverIndex === globalIndex || grid.mergeTargetSlot === root)
    readonly property bool tileDragging:
        tile !== null && tile.dragging
    readonly property AppTile tile: tileLoader.item as AppTile

    // AppTile's own z value only orders children inside this delegate. Raise
    // the slot as well so later Repeater delegates cannot cover the drag.
    z: tileDragging || (tile !== null && tile.dragReturnAnimationRunning)
        ? 1000 : (landingDragged && landingAnimationRunning ? 1 : 0)

    signal activated(int index)
    signal pointerSelected(int index)
    signal dragStateChanged(bool active)

    function openContextMenu(): void {
        if (tile) {
            tile.openContextMenuAtCenter();
        }
    }

    function captureVisual(relativeTo): var {
        if (!tile || !entry) {
            return null;
        }
        const snapshot = tile.captureVisual(relativeTo);
        snapshot.scale *= landingScale;
        return snapshot;
    }

    function settleFrom(snapshot, relativeTo): void {
        landingAnimation.stop();
        landingX = 0;
        landingY = 0;
        landingScale = 1;
        landingDragged = snapshot ? snapshot.dragged : false;
        if (!snapshot || !tileLoader.item || style.dragSettleDuration <= 0) {
            return;
        }
        const center = tileLoader.mapToItem(relativeTo,
            tileLoader.width / 2, tileLoader.height / 2);
        landingX = snapshot.center.x - center.x;
        landingY = snapshot.center.y - center.y;
        landingScale = snapshot.scale;
        if (Math.abs(landingX) > 0.25 || Math.abs(landingY) > 0.25
                || Math.abs(landingScale - 1) > 0.001) {
            landingAnimation.start();
        }
    }

    function clearLanding(): void {
        landingAnimation.stop();
        landingX = 0;
        landingY = 0;
        landingScale = 1;
    }

    ParallelAnimation {
        id: landingAnimation
        NumberAnimation {
            target: root
            properties: "landingX,landingY"
            to: 0
            duration: root.style.dragSettleDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "landingScale"
            to: 1
            duration: root.style.dragSettleDuration
            easing.type: Easing.OutCubic
        }
    }

    onEntryChanged: {
        if (entry !== null) {
            displayEntry = entry;
        }
        if (grid !== null && grid.mergeTargetSlot === root) {
            grid.resetMergeIntent();
        }
    }

    onShiftAnimationRunningChanged: {
        if (!shiftAnimationRunning && grid !== null && grid.dragging) {
            Qt.callLater(grid.refreshDragHover);
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 18, 56)
        height: 4
        radius: 2
        color: root.style.focusRing
        opacity: root.dropHoverActive && root.entry === null ? 0.85 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.style.hintDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    Loader {
        id: tileLoader
        anchors.centerIn: parent
        width: Math.min(root.style.tileWidth, parent.width)
        height: Math.min(root.style.tileHeight, parent.height)
        active: root.displayEntry !== null
        visible: root.entry !== null
        scale: root.landingScale

        // The drag preview translation is animated so the remaining icons
        // visibly slide aside, the way GNOME Shell's icon grid opens a gap.
        transform: [Translate {
            id: slotShift

            x: root.shiftOffset.x
            y: root.shiftOffset.y

            Behavior on x {
                enabled: root.shiftAnimationEnabled
                    && (root.shiftOffset.x !== 0 || slotShift.x !== 0)
                SmoothedAnimation {
                    id: shiftXAnimation
                    duration: root.style.dragShiftDuration
                    velocity: -1
                    maximumEasingTime: root.style.dragShiftDuration / 2
                    reversingMode: SmoothedAnimation.Immediate
                }
            }
            Behavior on y {
                enabled: root.shiftAnimationEnabled
                    && (root.shiftOffset.y !== 0 || slotShift.y !== 0)
                SmoothedAnimation {
                    id: shiftYAnimation
                    duration: root.style.dragShiftDuration
                    velocity: -1
                    maximumEasingTime: root.style.dragShiftDuration / 2
                    reversingMode: SmoothedAnimation.Immediate
                }
            }
        }, Translate {
            x: root.landingX
            y: root.landingY
        }]

        sourceComponent: AppTile {
            style: root.style
            controller: root.controller
            entry: root.displayEntry
            globalIndex: root.globalIndex
            sourceMode: root.sourceMode
            sourceFolderId: root.folderId
            selected: root.selected
            accessibleActive: root.accessibleActive && root.entry !== null
            dropMergePending: root.mergePending
            dropMergeArmed: root.mergeArmed
            dropMergeRevision: root.grid !== null ? root.grid.mergeDwellRevision : 0
            dropHoverActive: root.dropHoverActive
            dragPageOffsetX: root.dragPageOffsetX
            dragLayer: root.dragLayer
            layoutSettling: root.layoutSettling
            incomingAppId: root.incomingAppId
            launchSuppressed: root.entry !== null
                && root.entry.type === "app"
                && root.entry.id === root.suppressedAppId

            onActivated: {
                root.activated(root.globalIndex);
            }
            onHoveredChangedByPointer: hovered => {
                if (hovered) {
                    root.pointerSelected(root.globalIndex);
                }
            }
            onDragStateChanged: active => root.dragStateChanged(active)
            onMoveOutRequested: appId => root.controller.removeFromFolder(
                root.folderId, appId, -1)
            onUnpackRequested: folderId => root.controller.unpackFolder(folderId)
            onHideRequested: appId => root.controller.hideApplication(appId)
        }
    }

}
