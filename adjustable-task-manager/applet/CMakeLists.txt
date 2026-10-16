add_definitions(-DTRANSLATION_DOMAIN=\"plasma_applet_org.kde.plasma.adjustabletaskmanager\")

set_source_files_properties(qml/code/LayoutMetrics.js qml/code/TaskTools.js
    PROPERTIES QT_QML_SKIP_QMLDIR_ENTRY FALSE)

plasma_add_applet(org.kde.plasma.adjustabletaskmanager
    QML_SOURCES
        qml/AudioStream.qml
        qml/ConfigAppearance.qml
        qml/ConfigBehavior.qml
        qml/config.qml
        qml/ContextMenu.qml
        qml/GroupDialog.qml
        qml/GroupExpanderOverlay.qml
        qml/main.qml
        qml/MouseHandler.qml
        qml/PipeWireThumbnail.qml
        qml/PlayerController.qml
        qml/PulseAudio.qml
        qml/ScrollableTextWrapper.qml
        qml/TaskBadgeOverlay.qml
        qml/TaskList.qml
        qml/TaskProgressOverlay.qml
        qml/Task.qml
        qml/ToolTipDelegate.qml
        qml/ToolTipInstance.qml
        qml/ToolTipWindowMouseArea.qml
        qml/code/LayoutMetrics.js
        qml/code/TaskTools.js
    CPP_SOURCES
        applet.cpp
    RESOURCES
        main.xml
)

target_link_libraries(org.kde.plasma.adjustabletaskmanager PRIVATE
    Qt::Core
    Qt::Qml
    Qt::Quick
    KF6::CoreAddons
    KF6::I18n
    Plasma::Plasma)
