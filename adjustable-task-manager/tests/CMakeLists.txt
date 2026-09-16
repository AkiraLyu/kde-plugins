add_executable(task-manager-smoke smoke.cpp)
target_link_libraries(task-manager-smoke PRIVATE
    Qt6::Test Qt6::Widgets Qt6::Quick Plasma::Plasma Plasma::PlasmaQuick
    KF6::ConfigQml KF6::I18n PW::LibTaskManager)
add_dependencies(task-manager-smoke org.kde.plasma.adjustabletaskmanager)
add_test(NAME task-manager-smoke COMMAND task-manager-smoke)
set_tests_properties(task-manager-smoke PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=xcb;QT_QUICK_BACKEND=software;QT_PLUGIN_PATH=${CMAKE_BINARY_DIR}/bin"
    TIMEOUT 30)
