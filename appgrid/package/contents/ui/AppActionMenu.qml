pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

Item {
    id: root

    required property Item visualParent
    required property LayoutController controller
    required property var entry
    required property string sourceMode
    property string sourceFolderId: ""

    readonly property alias menu: contextMenu
    property var createdMenuObjects: []
    // Search providers can reorder their live model while a menu is open.
    // Dispatch every menu item against the entry that opened the menu.
    property var menuEntry: null

    signal activateRequested(var requestedEntry)
    signal moveOutRequested(string appId)
    signal unpackRequested(string folderId)
    signal hideRequested(string appId)

    width: 0
    height: 0

    function open(x, y): void {
        if (!entry || !entry.id) {
            return;
        }

        _clearMenu();
        menuEntry = entry;
        _fillMenu(contextMenu, _actionItems());
        contextMenu.popup(visualParent, x, y);
    }

    function _actionItems() {
        const targetEntry = menuEntry ?? entry;
        const items = [{
            text: targetEntry.type === "folder"
                ? i18nc("@action:inmenu", "Open Folder")
                : i18nc("@action:inmenu", "Launch"),
            icon: targetEntry.type === "folder"
                ? "folder-open" : "media-playback-start",
            appGridCommand: "activate",
        }];

        if (targetEntry.type === "app" || targetEntry.type === "runner") {
            const kdeActions = controller.actionsForEntry(targetEntry);
            if (kdeActions.length > 0) {
                items.push({type: "separator"});
                for (const action of kdeActions) {
                    items.push(action);
                }
            }
        }

        if (sourceMode === "folder") {
            items.push({type: "separator"});
            items.push({
                text: i18nc("@action:inmenu", "Move Out of Folder"),
                icon: "go-up",
                appGridCommand: "moveOut",
            });
        } else if (targetEntry.type === "folder") {
            items.push({type: "separator"});
            items.push({
                text: i18nc("@action:inmenu", "Unpack Folder"),
                icon: "folder-extract",
                appGridCommand: "unpack",
            });
        }

        if (targetEntry.type === "app") {
            items.push({type: "separator"});
            items.push({
                text: i18nc("@action:inmenu", "Hide Application"),
                icon: "view-hidden",
                appGridCommand: "hide",
            });
        }

        return items;
    }

    function _clearMenu(): void {
        contextMenu.close();
        for (let index = createdMenuObjects.length - 1; index >= 0; --index) {
            const record = createdMenuObjects[index];
            if (record.isMenu) {
                record.parentMenu.removeMenu(record.object);
            } else {
                record.parentMenu.removeItem(record.object);
            }
            record.object.destroy();
        }
        createdMenuObjects = [];
        menuEntry = null;
    }

    function _fillMenu(targetMenu, actionItems): void {
        for (const actionItem of actionItems) {
            if (actionItem.subActions) {
                const submenu = submenuComponent.createObject(root, {actionItem});
                createdMenuObjects.push({
                    object: submenu,
                    parentMenu: targetMenu,
                    isMenu: true,
                });
                targetMenu.addMenu(submenu);
                _fillMenu(submenu, actionItem.subActions);
            } else {
                const component = actionItem.type === "separator"
                    ? separatorComponent : menuItemComponent;
                const properties = actionItem.type === "separator"
                    ? {} : {actionItem};
                const menuItem = component.createObject(root, properties);
                createdMenuObjects.push({
                    object: menuItem,
                    parentMenu: targetMenu,
                    isMenu: false,
                });
                targetMenu.addItem(menuItem);
            }
        }
    }

    function _dispatch(actionItem): void {
        const targetEntry = menuEntry ?? entry;
        switch (actionItem.appGridCommand ?? "") {
        case "activate":
            activateRequested(targetEntry);
            return;
        case "moveOut":
            moveOutRequested(targetEntry.id);
            return;
        case "unpack":
            unpackRequested(targetEntry.id);
            return;
        case "hide":
            hideRequested(targetEntry.id);
            return;
        default:
            controller.triggerEntryAction(
                targetEntry,
                String(actionItem.actionId ?? ""),
                actionItem.actionArgument);
        }
    }

    QQC2.Menu {
        id: contextMenu
        parent: root.visualParent
        modal: true
        dim: false
    }

    Component {
        id: submenuComponent

        QQC2.Menu {
            required property var actionItem
            title: actionItem.text ?? ""
            icon.name: actionItem.icon ?? ""
        }
    }

    Component {
        id: menuItemComponent

        QQC2.MenuItem {
            required property var actionItem

            text: actionItem.text ?? ""
            enabled: actionItem.type !== "title" && (actionItem.enabled ?? true)
            checkable: actionItem.checkable ?? false
            checked: actionItem.checked ?? false
            icon.name: actionItem.icon ?? ""

            onTriggered: root._dispatch(actionItem)
        }
    }

    Component {
        id: separatorComponent
        QQC2.MenuSeparator {}
    }
}
