cmake_minimum_required(VERSION 3.22)

project(plasma_appgrid VERSION 0.3.0 LANGUAGES C CXX)

include(CTest)
include(GNUInstallDirs)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Qml Quick WaylandClient)
find_package(KF6Config REQUIRED)
find_package(KF6WindowSystem REQUIRED)

set(CMAKE_AUTOMOC ON)

set(APPGRID_CORE_URI_PATH org/kde/plasma/appgrid/core)
set(APPGRID_CORE_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/${APPGRID_CORE_URI_PATH}")
file(MAKE_DIRECTORY "${APPGRID_CORE_BUILD_DIR}")
add_library(appgridcoreplugin MODULE
    src/appgridcoreplugin.cpp
    src/searchindex.cpp
    src/searchindex.h
    src/pagemodel.h
)
target_compile_features(appgridcoreplugin PRIVATE cxx_std_17)
target_link_libraries(appgridcoreplugin PRIVATE Qt6::Core Qt6::Qml)
set_target_properties(appgridcoreplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${APPGRID_CORE_BUILD_DIR}"
)
foreach(CORE_METADATA qmldir appgridcore.qmltypes)
    configure_file(src/qml/core/${CORE_METADATA}
        "${APPGRID_CORE_BUILD_DIR}/${CORE_METADATA}" COPYONLY)
endforeach()
install(TARGETS appgridcoreplugin
    LIBRARY DESTINATION "${QT6_INSTALL_QML}/${APPGRID_CORE_URI_PATH}")
# install(FILES) also keeps symlinks as symlinks, so install the copies that
# configure_file already dereferenced into the build tree. A dangling qmldir
# makes every "import org.kde.plasma.appgrid.core" fail.
install(FILES
    "${APPGRID_CORE_BUILD_DIR}/qmldir"
    "${APPGRID_CORE_BUILD_DIR}/appgridcore.qmltypes"
    DESTINATION "${QT6_INSTALL_QML}/${APPGRID_CORE_URI_PATH}")

set(APPGRID_EFFECTS_URI_PATH org/kde/plasma/appgrid/effects)
set(APPGRID_EFFECTS_BUILD_DIR
    "${CMAKE_CURRENT_BINARY_DIR}/qml/${APPGRID_EFFECTS_URI_PATH}")
file(MAKE_DIRECTORY "${APPGRID_EFFECTS_BUILD_DIR}")

add_library(appgrideffectsplugin MODULE
    src/appgrideffectsplugin.cpp
    src/backgroundeffect.cpp
    src/backgroundeffect.h
)
target_compile_features(appgrideffectsplugin PRIVATE cxx_std_17)
target_link_libraries(appgrideffectsplugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::WaylandClient
    KF6::ConfigCore
    KF6::WindowSystem
    Wayland::Client
)
qt6_generate_wayland_protocol_client_sources(appgrideffectsplugin
    PRIVATE_CODE
    FILES "${CMAKE_CURRENT_SOURCE_DIR}/src/protocols/ext-background-effect-v1.xml"
)
set_target_properties(appgrideffectsplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${APPGRID_EFFECTS_BUILD_DIR}"
)

configure_file(
    src/qml/qmldir
    "${APPGRID_EFFECTS_BUILD_DIR}/qmldir"
    COPYONLY
)
configure_file(
    src/qml/appgrideffects.qmltypes
    "${APPGRID_EFFECTS_BUILD_DIR}/appgrideffects.qmltypes"
    COPYONLY
)

install(TARGETS appgrideffectsplugin
    LIBRARY DESTINATION "${QT6_INSTALL_QML}/${APPGRID_EFFECTS_URI_PATH}"
)
install(FILES
    "${APPGRID_EFFECTS_BUILD_DIR}/qmldir"
    "${APPGRID_EFFECTS_BUILD_DIR}/appgrideffects.qmltypes"
    DESTINATION "${QT6_INSTALL_QML}/${APPGRID_EFFECTS_URI_PATH}"
)

# Keep the UI as a regular KPackage; the small QML plugin above only observes
# the standardized Wayland background-effect global and reports its state.
# KWindowEffects remains the single owner of the per-surface effect object.
#
# install(DIRECTORY) always installs symlinks as symlinks and has no way to
# dereference them (FOLLOW_SYMLINK_CHAIN exists only for file(COPY)/file(INSTALL)).
# When package/ is made of relative symlinks into another tree -- a stowed
# dotfiles checkout, for instance -- those links keep their text but change
# depth, so every installed file points outside the prefix and dangles. Plasma
# then cannot read metadata.json and silently omits the applet from the widget
# explorer. -E copy_directory dereferences while copying, so stage the real
# files on every build and install that tree instead.
set(APPGRID_PACKAGE_STAGE "${CMAKE_CURRENT_BINARY_DIR}/package-staged")
add_custom_target(appgrid-package ALL
    COMMAND "${CMAKE_COMMAND}" -E remove_directory "${APPGRID_PACKAGE_STAGE}"
    COMMAND "${CMAKE_COMMAND}" -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/package" "${APPGRID_PACKAGE_STAGE}"
    COMMENT "Staging the appgrid plasmoid package"
    VERBATIM
)
install(
    DIRECTORY "${APPGRID_PACKAGE_STAGE}/"
    DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/plasma/plasmoids/org.kde.plasma.appgrid
)

if(BUILD_TESTING)
    # Some distributions keep a Qt 5 qmltestrunner in /usr/bin and the Qt 6
    # tool beside the Qt 6 private executables. Always resolve the latter.
    get_filename_component(
        QML_TEST_RUNNER
        "${Qt6_DIR}/../../qt6/bin/qmltestrunner"
        ABSOLUTE
    )
    if(NOT EXISTS "${QML_TEST_RUNNER}")
        message(FATAL_ERROR "Qt 6 qmltestrunner was not found at ${QML_TEST_RUNNER}")
    endif()

    get_filename_component(
        QML_LINTER
        "${Qt6_DIR}/../../qt6/bin/qmllint"
        ABSOLUTE
    )
    if(NOT EXISTS "${QML_LINTER}")
        message(FATAL_ERROR "Qt 6 qmllint was not found at ${QML_LINTER}")
    endif()

    file(GLOB_RECURSE APPGRID_QML_FILES CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/package/contents/*.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_*.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/manual/*.qml"
    )

    add_test(
        NAME appgrid-qml-tests
        COMMAND
            ${QML_TEST_RUNNER}
            -input ${CMAKE_CURRENT_SOURCE_DIR}/tests
            -import ${CMAKE_CURRENT_BINARY_DIR}/qml
            -import ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui
    )
    set_tests_properties(appgrid-qml-tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=;QML_DISABLE_DISK_CACHE=1;QT_LOGGING_RULES=kf.i18n.warning=false"
    )

    set(APPGRID_SCALE_NAMES 150 200)
    set(APPGRID_SCALE_FACTORS 1.5 2)
    foreach(SCALE_NAME SCALE_FACTOR IN ZIP_LISTS
            APPGRID_SCALE_NAMES APPGRID_SCALE_FACTORS)
        add_test(
            NAME appgrid-qml-scale-${SCALE_NAME}
            COMMAND
                ${QML_TEST_RUNNER}
                -silent
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_view.qml
                -import ${CMAKE_CURRENT_BINARY_DIR}/qml
                -import ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui
        )
        set_tests_properties(appgrid-qml-scale-${SCALE_NAME} PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=;QT_SCALE_FACTOR=${SCALE_FACTOR};QML_DISABLE_DISK_CACHE=1;QT_LOGGING_RULES=kf.i18n.warning=false"
        )
    endforeach()

    add_test(
        NAME appgrid-qmllint
        COMMAND
            ${QML_LINTER}
            -I ${CMAKE_CURRENT_BINARY_DIR}/qml
            -I ${CMAKE_CURRENT_SOURCE_DIR}/package/contents/ui
            ${APPGRID_QML_FILES}
    )
endif()
