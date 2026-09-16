pragma ComponentBehavior: Bound

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root

    required property AppGridStyle style
    required property LayoutController controller
    required property var entry
    required property int globalIndex
    required property string sourceMode
    property string sourceFolderId: ""
    property bool selected: false
    property bool accessibleActive: true
    property bool launchSuppressed: false
    property bool dropMergePending: false
    property bool dropMergeArmed: false
    property int dropMergeRevision: 0
    property bool dropHoverActive: false
    property real dragPageOffsetX: 0
    property Item dragLayer: null
    property bool dragEnabled: sourceMode !== "search"
    property bool touchDragArmed: false
    property bool suppressTouchTap: false
    property bool layoutSettling: false
    property string incomingAppId: ""
    property var dragEntry: null
    property point dragGrabOffset: Qt.point(0, 0)
    property point dragPointerScenePosition: Qt.point(0, 0)
    property real dropMergeProgress: 0
    readonly property var emptyEntry: ({
        type: "app",
        id: "",
        title: "",
        icon: "application-x-executable",
        description: "",
        category: "",
        previewIcons: [],
    })
    readonly property var safeEntry: dragEntry ?? entry ?? emptyEntry

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool pressed: pressHandler.pressed
        || touchTapHandler.pressed
    readonly property bool dragging: pointerDragHandler.active || touchDragHandler.active
    readonly property point dragVisualOffset: Qt.point(visual.x, visual.y)
    readonly property point dragVisualSceneCenter: visual.mapToItem(
        null, visual.width / 2, visual.height / 2)
    readonly property real visualScale: visual.scale
    readonly property bool dragVisualLifted: dragLayer !== null && visual.parent === dragLayer
    readonly property bool dragReturnAnimationRunning: dragReturnAnimation.running
    readonly property string draggedAppId: safeEntry.type === "app" ? safeEntry.id : ""
    readonly property bool applicationRunning: safeEntry.type === "app"
        && controller.isApplicationRunning(safeEntry.id)
    readonly property string supplementalDescription: {
        const description = String(safeEntry.description ?? "");
        const category = safeEntry.type === "runner"
            ? String(safeEntry.category ?? "") : "";
        if (category && description && category !== description) {
            return `${category} — ${description}`;
        }
        return category || description;
    }
    readonly property real iconDisplaySize: Math.max(0, Math.min(
        style.iconSize, width - 24, height - style.tileTextReserve))

    signal activated()
    signal hoveredChangedByPointer(bool hovered)
    signal dragStateChanged(bool active)
    signal moveOutRequested(string appId)
    signal unpackRequested(string folderId)
    signal hideRequested(string appId)

    function beginDrag(handler): void {
        dragReturnAnimation.stop();
        dragEntry = entry;
        // Track scene coordinates and keep the original grab point. A
        // threshold crossing, page slide or interrupted return must not
        // change the distance between the pointer and the lifted icon.
        const center = visual.mapToItem(null, width / 2, height / 2);
        const press = handler.centroid.scenePressPosition;
        dragGrabOffset = Qt.point(press.x - center.x, press.y - center.y);
        dragPointerScenePosition = handler.centroid.scenePosition;
        dragStateChanged(true);
        if (dragLayer) {
            // Cached ListView delegates can still be culled from rendering.
            // The lifted artwork must not belong to an offscreen page.
            visual.parent = dragLayer;
        }
        updateDragVisualPosition();
    }

    function updateDragVisualPosition(): void {
        const center = visual.parent.mapFromItem(null,
            dragPointerScenePosition.x - dragGrabOffset.x,
            dragPointerScenePosition.y - dragGrabOffset.y);
        visual.x = center.x - width / 2;
        visual.y = center.y - height / 2;
    }

    function captureVisual(relativeTo): var {
        return {
            entry: safeEntry,
            center: visual.mapToItem(relativeTo, width / 2, height / 2),
            scale: visual.scale,
            dragged: dragEntry !== null,
            iconRect: iconContainer.mapToItem(relativeTo,
                Qt.rect(0, 0, iconContainer.width, iconContainer.height)),
        };
    }

    onDropMergePendingChanged: {
        if (dropMergePending) {
            dropMergeProgress = 0;
            mergeProgressAnimation.restart();
        } else if (!dropMergeArmed) {
            mergeProgressAnimation.stop();
            dropMergeProgress = 0;
        }
    }

    onDropMergeRevisionChanged: {
        if (dropMergePending) {
            mergeProgressAnimation.stop();
            dropMergeProgress = 0;
            mergeProgressAnimation.start();
        }
    }

    onDropMergeArmedChanged: {
        if (dropMergeArmed) {
            mergeProgressAnimation.stop();
            dropMergeProgress = 1;
        } else if (!dropMergePending) {
            dropMergeProgress = 0;
        }
    }

    onDragPageOffsetXChanged: {
        if (dragging) {
            updateDragVisualPosition();
        }
    }

    NumberAnimation {
        id: mergeProgressAnimation
        target: root
        property: "dropMergeProgress"
        to: 1
        duration: root.style.tileFeedbackDuration > 0
            ? (root.safeEntry.type === "folder"
                ? root.style.dragExistingFolderMergeDelay
                : root.style.dragMergeDelay)
            : 0
        easing.type: Easing.Linear
    }

    function openContextMenuAtCenter(): void {
        actionMenu.open(width / 2, Math.min(height / 2, iconDisplaySize));
    }

    function finishDrag(): void {
        // Keep the grid's gap and source identity alive through dispatch so
        // it can capture the rendered positions before changing the model.
        const action = visual.Drag.drop();
        const accepted = action !== Qt.IgnoreAction;
        const center = visual.mapToItem(root, width / 2, height / 2);
        visual.parent = root;
        if (accepted) {
            visual.x = 0;
            visual.y = 0;
        } else {
            visual.x = center.x - width / 2;
            visual.y = center.y - height / 2;
            Qt.callLater(() => {
                if (!root.dragging) {
                    dragReturnAnimation.restart();
                }
            });
        }
        dragEntry = null;
        dragStateChanged(false);
    }

    // The pointer never passes through a Behavior. A separate, interruptible
    // animation owns only rejected drops, including the first threshold frame.
    ParallelAnimation {
        id: dragReturnAnimation
        NumberAnimation {
            target: visual
            properties: "x,y"
            to: 0
            duration: root.style.tileMoveDuration
            easing.type: Easing.OutCubic
        }
    }

    Accessible.name: safeEntry.title
    Accessible.description: safeEntry.type === "folder"
        ? i18ncp(
            "@info:accessibility",
            "%1 application", "%1 applications",
            safeEntry.apps ? safeEntry.apps.length : 0)
        : (applicationRunning
            ? (supplementalDescription.length > 0
                ? i18nc("@info:accessibility", "Running — %1",
                    supplementalDescription)
                : i18nc("@info:accessibility", "Running"))
            : supplementalDescription)
    Accessible.role: Accessible.Button
    Accessible.ignored: !accessibleActive
    Accessible.focusable: true
    Accessible.focused: selected
    Accessible.selectable: true
    Accessible.selected: selected
    Accessible.onPressAction: root.activated()

    Item {
        id: visual
        x: 0
        y: 0
        width: root.width
        height: root.height
        z: root.dragging ? 1000 : 0
        scale: root.layoutSettling ? 1
            : (root.dragging || root.touchDragArmed ? root.style.tileLiftScale
            : (root.dropMergeArmed ? 1.035
                : (root.dropMergePending ? 1.02
                    : (root.pressed ? 0.96 : 1))))

        Drag.active: root.dragging
        Drag.source: root
        Drag.keys: ["plasma-appgrid-item"]
        Drag.supportedActions: Qt.MoveAction
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: Math.min(height / 2, root.iconDisplaySize / 2 + 18)

        Behavior on scale {
            enabled: !root.layoutSettling
            NumberAnimation {
                duration: root.dragging
                    ? root.style.tileLiftDuration
                    : (root.pressed
                        ? root.style.tilePressDuration
                        : root.style.tileReleaseDuration)
                easing.type: root.dragging
                    ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 0.65
            }
        }

        Rectangle {
            id: tileBackground
            objectName: "appGridTileBackground"
            anchors.fill: parent
            anchors.margins: 3
            radius: root.style.cornerRadius
            color: root.dragging ? "transparent"
                : pressHandler.pressed || touchTapHandler.pressed
                ? root.style.tilePressed
                : (root.selected || root.hovered ? root.style.tileHover : "transparent")
            // The merge halo replaces the ordinary selection outline while a
            // drop is being confirmed, avoiding two competing focus rings.
            border.width: root.selected
                    && !root.dragging
                    && !root.dropMergePending && !root.dropMergeArmed
                ? 2 : 0
            border.color: root.style.focusRing

            Behavior on color {
                ColorAnimation { duration: root.style.hintDuration }
            }
        }

        Item {
            id: iconContainer
            objectName: "appGridIconContainer"
            anchors.top: parent.top
            anchors.topMargin: root.style.tileTopPadding
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.iconDisplaySize
            height: root.iconDisplaySize
            opacity: root.launchSuppressed ? 0 : 1

            AppIcon {
                id: iconArtwork
                anchors.fill: parent
                style: root.style
                entry: root.safeEntry
                previewFolder: root.dropMergeArmed
                incomingAppId: root.incomingAppId
                animate: !root.layoutSettling
                rightToLeft: root.LayoutMirroring.enabled
            }
        }

        Item {
            id: mergeHalo
            anchors.centerIn: iconContainer
            width: iconContainer.width + 20
            height: iconContainer.height + 20
            opacity: root.dropMergeArmed ? 1
                : (root.dropMergePending ? 0.78 : 0)
            scale: 0.86 + 0.14 * root.dropMergeProgress
            Accessible.ignored: true

            Rectangle {
                anchors.fill: parent
                radius: Math.max(root.style.cornerRadius, width * 0.24)
                color: "transparent"
                border.width: root.dropMergeArmed ? 3 : 2
                border.color: root.style.focusRing
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.style.tileFeedbackDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        PlasmaComponents.Label {
            id: appLabel
            objectName: "appGridApplicationLabel"

            anchors.top: iconContainer.bottom
            anchors.topMargin: root.style.tileIconLabelSpacing
            anchors.left: parent.left
            anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.rightMargin: 9
            height: Math.max(0, Math.min(
                implicitHeight,
                root.style.applicationLabelHeight,
                parent.height - y - root.style.tileBottomPadding))
            text: root.safeEntry.title
            color: root.style.foreground
            opacity: root.dragging ? 0 : 1
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            font.pointSize: root.style.applicationLabelPointSize
            textFormat: Text.PlainText
            // The tile itself exposes the label, description, selection and
            // press action. A second text accessible would make screen
            // readers announce every application twice and leak labels from
            // lazily hidden pages after the button has been ignored.
            Accessible.ignored: true

            Behavior on opacity {
                NumberAnimation {
                    duration: root.style.tileFeedbackDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            id: runningIndicator

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -6
            width: 5
            height: 5
            radius: 2.5
            visible: root.applicationRunning || opacity > 0.001
            opacity: root.applicationRunning ? 1 : 0
            scale: root.applicationRunning ? 1 : 0.55
            color: root.style.foreground
            Accessible.ignored: true

            Behavior on opacity {
                NumberAnimation { duration: root.style.tileFeedbackDuration }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: root.style.tileReleaseDuration
                    easing.type: Easing.OutBack
                }
            }
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled
        onHoveredChanged: root.hoveredChangedByPointer(hovered)
    }

    TapHandler {
        id: pressHandler
        // Qt Wayland reports a click from a physical touchpad as TouchPad,
        // even though it is an ordinary seat-pointer click. Treat it exactly
        // like mouse/stylus input; touchscreen taps retain their dedicated
        // long-press path below.
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            | PointerDevice.Stylus
        acceptedButtons: Qt.LeftButton
        enabled: root.enabled
        gesturePolicy: TapHandler.DragThreshold
        onTapped: root.activated()
    }

    TapHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            | PointerDevice.Stylus
        acceptedButtons: Qt.RightButton
        enabled: root.enabled
        onTapped: eventPoint => actionMenu.open(
            eventPoint.position.x, eventPoint.position.y)
    }

    DragHandler {
        id: pointerDragHandler
        enabled: root.enabled && root.dragEnabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            | PointerDevice.Stylus | PointerDevice.Puck
        // The surrounding horizontal ListView also observes the press for
        // paging. Once this handler crosses the drag threshold it must be able
        // to take the exclusive grab so the icon, rather than the page, moves.
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        dragThreshold: root.style.pointerDragThreshold
        // Scene positioning also updates the actual Drag hot spot when the
        // source page or a settling slot moves underneath the pointer.
        target: null
        xAxis.minimum: -10000
        xAxis.maximum: 10000
        yAxis.minimum: -10000
        yAxis.maximum: 10000

        onActiveChanged: {
            if (active) {
                root.beginDrag(pointerDragHandler);
            } else {
                root.finishDrag();
            }
        }
        onCentroidChanged: {
            if (active) {
                root.dragPointerScenePosition = centroid.scenePosition;
                root.updateDragVisualPosition();
            }
        }
    }

    TapHandler {
        id: touchTapHandler
        acceptedDevices: PointerDevice.TouchScreen
        acceptedButtons: Qt.LeftButton
        enabled: root.enabled
        gesturePolicy: TapHandler.DragThreshold
        longPressThreshold: 0.42

        onLongPressed: {
            if (root.dragEnabled) {
                root.suppressTouchTap = true;
                root.touchDragArmed = true;
            }
        }
        onTapped: {
            if (!root.suppressTouchTap) {
                root.activated();
            }
        }
        onPressedChanged: {
            if (!pressed) {
                touchReleaseTimer.restart();
            }
        }
    }

    DragHandler {
        id: touchDragHandler
        // Keep observing the touch point before the long press. Enabling a
        // handler only after the press can make it miss the existing point on
        // some Qt/Wayland combinations. The effectively unreachable threshold
        // lets the surrounding ListView own normal swipe gestures; arming the
        // drag drops it to zero for the next movement.
        enabled: root.enabled && root.dragEnabled
        acceptedDevices: PointerDevice.TouchScreen
        acceptedButtons: Qt.LeftButton
        dragThreshold: root.touchDragArmed
            ? root.style.touchDragThreshold : 32767
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        target: null
        xAxis.minimum: -10000
        xAxis.maximum: 10000
        yAxis.minimum: -10000
        yAxis.maximum: 10000

        onActiveChanged: {
            if (active) {
                root.beginDrag(touchDragHandler);
            } else {
                root.finishDrag();
            }
        }
        onCentroidChanged: {
            if (active) {
                root.dragPointerScenePosition = centroid.scenePosition;
                root.updateDragVisualPosition();
            }
        }
    }

    Timer {
        id: touchReleaseTimer
        interval: 0
        onTriggered: {
            root.touchDragArmed = false;
            root.suppressTouchTap = false;
        }
    }

    AppActionMenu {
        id: actionMenu
        visualParent: root
        controller: root.controller
        entry: root.safeEntry
        sourceMode: root.sourceMode
        sourceFolderId: root.sourceFolderId

        onActivateRequested: requestedEntry => {
            // Preserve selection and folder-origin animation if this slot has
            // not changed. Otherwise activate the menu's entry snapshot.
            if (requestedEntry === root.safeEntry) {
                root.activated();
            } else {
                root.controller.activateEntry(requestedEntry);
            }
        }
        onMoveOutRequested: appId => root.moveOutRequested(appId)
        onUnpackRequested: folderId => root.unpackRequested(folderId)
        onHideRequested: appId => root.hideRequested(appId)
    }

    PlasmaComponents.ToolTip {
        visible: root.accessibleActive && root.hovered && !root.dragging
            && !root.dropHoverActive
            && root.supplementalDescription.length > 0
        text: root.supplementalDescription
        delay: Kirigami.Units.toolTipDelay
    }
}
