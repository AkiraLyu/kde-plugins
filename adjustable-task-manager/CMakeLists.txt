cmake_minimum_required(VERSION 3.22)

project(adjustable-task-manager VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM 6.26 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs6)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 6.10 REQUIRED COMPONENTS Core Qml Quick)
find_package(KF6 6.26 REQUIRED COMPONENTS Config I18n KIO Notifications Service WindowSystem)
find_package(Plasma 6.7 REQUIRED)
find_package(PlasmaActivities 6.7 REQUIRED)
find_package(PlasmaActivitiesStats 6.7 REQUIRED)
find_package(KSysGuard REQUIRED)
find_package(LibNotificationManager 6.7 REQUIRED)

add_subdirectory(applet)

ki18n_install(po)

if(BUILD_TESTING)
    find_package(Qt6 6.10 REQUIRED COMPONENTS Test Widgets)
    find_package(PlasmaQuick 6.7 REQUIRED)
    find_package(LibTaskManager 6.7 REQUIRED)
    add_subdirectory(tests)
endif()
