find_package(Python3 REQUIRED COMPONENTS Interpreter)
find_package(KWayland 6.8 REQUIRED)
find_program(DBUS_RUN_SESSION dbus-run-session REQUIRED)
find_program(KWIN_WAYLAND kwin_wayland REQUIRED)

add_executable(task-manager-smoke smoke.cpp)
target_link_libraries(task-manager-smoke PRIVATE
    Qt6::Test Qt6::Widgets Qt6::Quick Plasma::Plasma Plasma::PlasmaQuick
    KF6::ConfigQml KF6::I18n Plasma::KWaylandClient PW::LibTaskManager)
add_dependencies(task-manager-smoke org.kde.plasma.adjustabletaskmanager)
add_test(NAME task-manager-smoke COMMAND
    ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/run-smoke.py
    ${DBUS_RUN_SESSION} ${KWIN_WAYLAND} $<TARGET_FILE:task-manager-smoke>)
set_tests_properties(task-manager-smoke PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=wayland;QT_QUICK_BACKEND=software;QT_PLUGIN_PATH=${CMAKE_BINARY_DIR}/bin"
    TIMEOUT 90)
