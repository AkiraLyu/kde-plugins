pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

FocusScope {
    id: root

    required property AppGridStyle style
    required property LayoutController controller
    // Kicker.DashboardWindow delivers keyboard events to keyEventProxy rather
    // than relying solely on the QML focus item. Route that proxy to the
    // editor for the duration of a rename or typed characters keep going to
    // the folder-navigation sink despite the field's visual focus.
    readonly property Item keyEventProxy:
        folderDialog.nameEditing && folderDialog.nameEditor
            ? folderDialog.nameEditor
            : (activeFolderId ? modalKeySink : searchBox.inputItem)
    readonly property bool searching: searchBox.text.trim().length > 0
    readonly property alias grid: appGrid
    readonly property alias folderGrid: folderDialog.grid
    readonly property point folderAnimationOrigin: folderDialog.originPoint
    readonly property bool folderNameEditing: folderDialog.nameEditing
    readonly property Item folderNameEditor: folderDialog.nameEditor
    readonly property real contentOpacity: content.opacity
    readonly property real contentScale: content.scale
    readonly property real backdropOpacity: backdrop.opacity
    readonly property bool transitionRunning: entranceAnimation.running
        || exitAnimation.running
    readonly property bool launchFeedbackRunning: launchAnimation.running
    readonly property real launchFeedbackOpacity: launchClone.opacity
    readonly property real launchFeedbackWidth: launchClone.width
    readonly property real launchFeedbackScale: launchClone.scale
    readonly property real folderRevealProgress: folderDialog.revealProgress
    readonly property real folderScrimOpacity: folderDialog.scrimOpacity
    readonly property real folderPanelOpacity: folderDialog.panelOpacity
    readonly property real folderPanelScale: folderDialog.panelScale
    readonly property bool folderTransitionActive: folderDialog.transitionActive
    readonly property bool backgroundAccessibilityEnabled:
        searchBox.accessibilityEnabled
    property alias searchText: searchBox.text
    property string activeFolderId: ""
    property var pendingLaunchEntry: null
    property rect pendingLaunchRect: Qt.rect(0, 0, 0, 0)
    property bool launchActivationPending: false
    property string suppressedLaunchAppId: ""
    property int layoutDirectionOverride: -1
    readonly property bool rightToLeft: layoutDirectionOverride >= 0
        ? layoutDirectionOverride === Qt.RightToLeft
        : Application.layoutDirection === Qt.RightToLeft

    signal closeRequested()
    signal exitFinished()

    onActiveFolderIdChanged: {
        if (root.activeFolderId) {
            modalKeySink.forceActiveFocus(Qt.OtherFocusReason);
        } else {
            searchBox.takeFocus(Qt.OtherFocusReason);
        }
    }

    LayoutMirroring.enabled: rightToLeft
    LayoutMirroring.childrenInherit: true
    Accessible.name: i18nc("@title", "Applications")
    Accessible.role: Accessible.Pane

    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: root.style.backdrop
        opacity: 0
    }

    TapHandler {
        onTapped: eventPoint => {
            if (folderDialog.opened) {
                return;
            }

            const gridPoint = appGrid.mapFromItem(root, eventPoint.position);
            const searchPoint = searchBox.mapFromItem(root, eventPoint.position);
            const insideGrid = gridPoint.x >= 0 && gridPoint.y >= 0
                && gridPoint.x <= appGrid.width
                && gridPoint.y <= appGrid.height;
            const insideSearch = searchPoint.x >= 0 && searchPoint.y >= 0
                && searchPoint.x <= searchBox.width && searchPoint.y <= searchBox.height;
            if (!insideGrid && !insideSearch) {
                root.closeRequested();
            }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0
        scale: root.style.overviewInitialScale
        transformOrigin: Item.Center
        enabled: !root.launchActivationPending

        SearchBox {
            id: searchBox
            anchors.top: parent.top
            anchors.topMargin: Math.max(28, Math.min(68, parent.height * 0.065))
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(root.style.searchWidth, parent.width * 0.74)
            style: root.style
            layoutDirectionOverride: root.layoutDirectionOverride
            enabled: !folderDialog.opened
            accessibilityEnabled: !folderDialog.opened
            placeholderText: i18nc("@info:placeholder", "Type to search")

            onTextChanged: {
                root.controller.searchText = text;
                if (text.trim().length > 0 && root.activeFolderId) {
                    root.activeFolderId = "";
                }
                // Local matching is synchronous. Reset immediately so rapid
                // input cannot queue stale page resets a frame behind text.
                appGrid.resetSearchPosition();
            }
            onEscapePressed: root.handleEscape()
            onNavigationPressed: (key, modifiers) => {
                if (root.activeFolderId) {
                    folderDialog.grid.navigate(key, modifiers);
                } else {
                    appGrid.navigate(key, modifiers);
                }
            }
            onActivationPressed: {
                if (root.activeFolderId) {
                    folderDialog.grid.activateSelected();
                } else {
                    appGrid.activateSelected();
                }
            }
            onContextMenuPressed: {
                if (root.activeFolderId) {
                    folderDialog.grid.openSelectedContextMenu();
                } else {
                    appGrid.openSelectedContextMenu();
                }
            }
            onRenamePressed: root.beginFolderRename()
        }

        QQC2.ToolButton {
            id: restoreHiddenButton
            anchors.top: searchBox.top
            anchors.right: parent.right
            anchors.rightMargin: Math.max(22, parent.width * 0.035)
            width: 48
            height: 48
            visible: root.controller.hiddenApplicationCount > 0
            enabled: !folderDialog.opened
            icon.name: "view-visible"
            icon.color: root.style.foreground
            display: QQC2.AbstractButton.IconOnly
            onClicked: root.controller.restoreHiddenApplications()
            background: Rectangle {
                radius: width / 2
                color: restoreHiddenButton.hovered
                    ? root.style.tileHover : "transparent"
            }

            Accessible.name: i18nc(
                "@action:button", "Restore hidden applications")
            Accessible.ignored: !visible || folderDialog.opened

            PlasmaComponents.ToolTip {
                visible: restoreHiddenButton.hovered
                text: i18nc("@info:tooltip", "Restore hidden applications")
            }
        }

        PagedGrid {
            id: appGrid
            anchors.top: searchBox.bottom
            anchors.topMargin: Math.max(18, parent.height * 0.025)
            anchors.left: parent.left
            anchors.leftMargin: Math.max(70, parent.width * 0.10)
            anchors.right: parent.right
            anchors.rightMargin: Math.max(70, parent.width * 0.10)
            anchors.bottom: pageDots.top
            anchors.bottomMargin: 18
            style: root.style
            controller: root.controller
            sourceMode: root.searching ? "search" : "root"
            activationHandledExternally: true
            suppressedAppId: root.suppressedLaunchAppId
            layoutDirectionOverride: root.layoutDirectionOverride
            // FolderDialog is modal. Its TapHandler handles outside clicks,
            // while disabling this subtree prevents passive HoverHandlers and
            // TapHandlers from also reacting through the translucent scrim.
            enabled: !folderDialog.opened
            accessibilityEnabled: !folderDialog.opened

            onItemActivated: index => {
                const entry = root.controller.entryAt(
                    appGrid.sourceMode, index, "");
                if (entry && entry.type === "folder") {
                    const itemRect = appGrid.itemRect(index);
                    folderDialog.originPoint = folderDialog.mapFromItem(
                        appGrid,
                        itemRect.x + itemRect.width / 2,
                        itemRect.y + itemRect.height / 2);
                }
                searchBox.takeFocus(Qt.OtherFocusReason);
                root.requestActivation(entry, appGrid, index);
            }
        }

        PageDots {
            id: pageDots
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(28, Math.min(52, parent.height * 0.045))
            style: root.style
            pageCount: appGrid.pageCount
            currentPosition: appGrid.pagePosition
            enabled: !folderDialog.opened
            accessibilityEnabled: !folderDialog.opened
            onPageRequested: page => appGrid.goToPage(page, true)
        }

        QQC2.ToolButton {
            id: previousButton
            anchors.verticalCenter: appGrid.verticalCenter
            x: appGrid.rightToLeft
                ? parent.width - width - Math.max(14, parent.width * 0.025)
                : Math.max(14, parent.width * 0.025)
            width: 52
            height: 52
            visible: appGrid.currentPage > 0 && !folderDialog.opened
            icon.name: root.rightToLeft
                ? "go-next-symbolic" : "go-previous-symbolic"
            icon.color: root.style.foreground
            display: QQC2.AbstractButton.IconOnly
            onClicked: appGrid.goToPage(appGrid.currentPage - 1, true)
            background: Rectangle {
                radius: width / 2
                color: previousButton.hovered ? root.style.tileHover : "transparent"
            }

            Accessible.name: i18nc("@action:button", "Previous page")
            Accessible.ignored: !visible
        }

        QQC2.ToolButton {
            id: nextButton
            anchors.verticalCenter: appGrid.verticalCenter
            x: appGrid.rightToLeft
                ? Math.max(14, parent.width * 0.025)
                : parent.width - width - Math.max(14, parent.width * 0.025)
            width: 52
            height: 52
            visible: appGrid.currentPage < appGrid.pageCount - 1 && !folderDialog.opened
            icon.name: root.rightToLeft
                ? "go-previous-symbolic" : "go-next-symbolic"
            icon.color: root.style.foreground
            display: QQC2.AbstractButton.IconOnly
            onClicked: appGrid.goToPage(appGrid.currentPage + 1, true)
            background: Rectangle {
                radius: width / 2
                color: nextButton.hovered ? root.style.tileHover : "transparent"
            }

            Accessible.name: i18nc("@action:button", "Next page")
            Accessible.ignored: !visible
        }

        Column {
            anchors.centerIn: appGrid
            spacing: 14
            visible: root.searching && root.controller.searchCount === 0

            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72
                height: 72
                visible: !root.controller.searchQuerying
                source: "edit-find-symbolic"
                color: root.style.secondaryForeground
                Accessible.ignored: true
            }

            QQC2.BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64
                visible: root.controller.searchQuerying
                running: visible
                Accessible.ignored: !visible
            }

            PlasmaComponents.Label {
                text: root.controller.searchQuerying
                    ? i18nc("@info", "Searching…")
                    : i18nc("@info", "No results")
                color: root.style.secondaryForeground
                font.pointSize: root.style.searchFontPointSize
                Accessible.ignored: !parent.visible
            }
        }

        FolderDialog {
            id: folderDialog
            anchors.fill: parent
            style: root.style
            controller: root.controller
            folderId: root.activeFolderId
            suppressedAppId: root.suppressedLaunchAppId
            layoutDirectionOverride: root.layoutDirectionOverride
            onCloseRequested: {
                root.activeFolderId = "";
                searchBox.takeFocus(Qt.OtherFocusReason);
            }
            onNameEditEnded:
                modalKeySink.forceActiveFocus(Qt.OtherFocusReason)
            onItemActivated: index => root.requestActivation(
                root.controller.entryAt("folder", index, root.activeFolderId),
                folderDialog.grid, index)
        }
    }

    Item {
        id: launchLayer

        anchors.fill: parent
        z: 4000
        enabled: false
        Accessible.ignored: true

        Kirigami.Icon {
            id: launchClone

            visible: root.launchFeedbackRunning || opacity > 0
            source: root.pendingLaunchEntry
                ? root.pendingLaunchEntry.icon : ""
            smooth: true
            transformOrigin: Item.Center
            opacity: 0
            scale: 1
        }
    }

    TextInput {
        id: modalKeySink

        objectName: "appGridModalKeySink"
        width: 1
        height: 1
        opacity: 0
        readOnly: true
        cursorVisible: false
        Accessible.ignored: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => searchBox.handleKeyEvent(event)
    }

    ParallelAnimation {
        id: launchAnimation

        onFinished: root.commitPendingLaunch()

        NumberAnimation {
            target: launchClone
            property: "scale"
            from: 1
            to: root.style.appLaunchScale
            duration: root.style.appLaunchDuration
            easing.type: Easing.OutCubic
        }

        SequentialAnimation {
            PauseAnimation {
                // Keep the clone crisp while it lifts away from the source.
                // An early, long fade made the enlarged icon overlap its
                // original as a translucent double image.
                duration: Math.round(root.style.appLaunchDuration * 0.58)
            }
            NumberAnimation {
                target: launchClone
                property: "opacity"
                from: 1
                to: 0
                duration: Math.max(0, root.style.appLaunchDuration
                    - Math.round(root.style.appLaunchDuration * 0.58))
                easing.type: Easing.InCubic
            }
        }
    }

    Timer {
        id: launchSuppressionTimer

        interval: root.style.exitDuration
        onTriggered: root.suppressedLaunchAppId = ""
    }

    ParallelAnimation {
        id: entranceAnimation

        NumberAnimation {
            target: backdrop
            property: "opacity"
            from: 0
            to: 1
            duration: root.style.entranceDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: content
            property: "opacity"
            from: 0
            to: 1
            duration: root.style.entranceDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: content
            property: "scale"
            from: root.style.overviewInitialScale
            to: 1
            duration: root.style.entranceScaleDuration
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: exitAnimation

        onFinished: root.exitFinished()

        NumberAnimation {
            id: exitBackdropAnimation

            target: backdrop
            property: "opacity"
            to: 0
            duration: root.style.exitDuration
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            id: exitOpacityAnimation

            target: content
            property: "opacity"
            to: 0
            duration: root.style.exitDuration
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            id: exitScaleAnimation

            target: content
            property: "scale"
            to: root.style.overviewExitScale
            duration: root.style.exitDuration
            easing.type: Easing.InCubic
        }
    }

    Connections {
        target: root.controller

        function onFolderOpenRequested(folderId): void {
            root.activeFolderId = folderId;
            folderDialog.grid.reset();
        }

        function onSearchTextChanged(): void {
            if (searchBox.text !== root.controller.searchText) {
                searchBox.text = root.controller.searchText;
            }
        }

    }

    function reset(): void {
        clearLaunchFeedback();
        activeFolderId = "";
        searchBox.clear();
        controller.searchText = "";
        appGrid.reset();
        searchBox.takeFocus(Qt.OtherFocusReason);
    }

    function playEntrance(): void {
        exitAnimation.stop();
        entranceAnimation.stop();
        backdrop.opacity = 0;
        content.opacity = 0;
        content.scale = style.overviewInitialScale;
        entranceAnimation.restart();
        searchBox.takeFocus(Qt.OtherFocusReason);
    }

    function playExit(): void {
        entranceAnimation.stop();
        exitAnimation.stop();
        exitBackdropAnimation.from = backdrop.opacity;
        exitOpacityAnimation.from = content.opacity;
        exitScaleAnimation.from = content.scale;
        exitAnimation.restart();
    }

    function cancelTransitions(): void {
        entranceAnimation.stop();
        exitAnimation.stop();
    }

    function prepareLaunchFeedback(entry, grid, index): bool {
        if (!entry || entry.type !== "app" || !grid) {
            pendingLaunchEntry = null;
            pendingLaunchRect = Qt.rect(0, 0, 0, 0);
            return false;
        }

        const cellRect = grid.itemRect(index);
        if (cellRect.width <= 0 || cellRect.height <= 0) {
            return false;
        }
        const topLeft = grid.mapToItem(
            root, cellRect.x, cellRect.y);
        const bottomRight = grid.mapToItem(
            root, cellRect.x + cellRect.width,
            cellRect.y + cellRect.height);
        const mappedX = Math.min(topLeft.x, bottomRight.x);
        const mappedY = Math.min(topLeft.y, bottomRight.y);
        const mappedWidth = Math.abs(bottomRight.x - topLeft.x);
        const mappedHeight = Math.abs(bottomRight.y - topLeft.y);
        const transformScale = cellRect.width > 0
            ? mappedWidth / cellRect.width : 1;
        const tileHeight = Math.min(style.tileHeight, cellRect.height)
            * transformScale;
        const iconSize = Math.max(0, Math.min(
            style.iconSize,
            cellRect.width - 24,
            tileHeight - style.tileTextReserve)) * transformScale;

        pendingLaunchEntry = entry;
        pendingLaunchRect = Qt.rect(
            mappedX + (mappedWidth - iconSize) / 2,
            mappedY + (mappedHeight - tileHeight) / 2
                + style.tileTopPadding * transformScale,
            iconSize,
            iconSize);
        return iconSize > 0;
    }

    function requestActivation(entry, grid, index): void {
        if (!entry || launchActivationPending) {
            return;
        }

        // Running applications switch directly to their existing window.
        // Folders and runner results also do not need process-start feedback.
        if (entry.type !== "app"
                || controller.isApplicationRunning(entry.id)
                || style.appLaunchDuration <= 0
                || !prepareLaunchFeedback(entry, grid, index)) {
            clearLaunchFeedback();
            controller.activateEntry(entry);
            return;
        }

        startLaunchFeedback();
    }

    function startLaunchFeedback(): void {
        if (!pendingLaunchEntry || pendingLaunchRect.width <= 0) {
            return;
        }

        launchAnimation.stop();
        const start = pendingLaunchRect;
        launchClone.x = start.x;
        launchClone.y = start.y;
        launchClone.width = start.width;
        launchClone.height = start.height;
        launchClone.opacity = 1;
        launchClone.scale = 1;
        suppressedLaunchAppId = String(pendingLaunchEntry.id ?? "");
        launchActivationPending = true;
        launchAnimation.restart();
    }

    function commitPendingLaunch(): void {
        const entry = pendingLaunchEntry;
        launchActivationPending = false;
        launchClone.opacity = 0;
        launchClone.scale = 1;
        launchClone.width = 0;
        launchClone.height = 0;
        pendingLaunchEntry = null;
        pendingLaunchRect = Qt.rect(0, 0, 0, 0);
        if (suppressedLaunchAppId) {
            launchSuppressionTimer.restart();
        }
        if (entry) {
            controller.activateEntry(entry);
        }
    }

    function clearLaunchFeedback(): void {
        launchAnimation.stop();
        launchSuppressionTimer.stop();
        launchActivationPending = false;
        suppressedLaunchAppId = "";
        launchClone.opacity = 0;
        launchClone.scale = 1;
        launchClone.width = 0;
        launchClone.height = 0;
        pendingLaunchEntry = null;
        pendingLaunchRect = Qt.rect(0, 0, 0, 0);
    }

    function beginFolderRename(): void {
        if (activeFolderId) {
            folderDialog.beginRename();
        }
    }

    function handleEscape(): void {
        if (activeFolderId) {
            if (folderDialog.cancelRename()) {
                return;
            }
            activeFolderId = "";
            searchBox.takeFocus(Qt.OtherFocusReason);
        } else if (searchBox.text.length > 0) {
            searchBox.clear();
        } else {
            closeRequested();
        }
    }
}
