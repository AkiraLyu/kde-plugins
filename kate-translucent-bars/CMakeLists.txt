cmake_minimum_required(VERSION 3.22)

project(kate-translucent-bars VERSION 1.2.0 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Qt6 6.5 REQUIRED COMPONENTS Widgets)
find_package(KF6CoreAddons 6.0 REQUIRED)
find_package(KF6TextEditor 6.0 REQUIRED)
find_package(KF6WidgetsAddons 6.0 REQUIRED)

add_library(katetranslucentbarsplugin MODULE
    katetranslucentbarsplugin.cpp
)

target_link_libraries(katetranslucentbarsplugin PRIVATE
    Qt6::Widgets
    KF6::CoreAddons
    KF6::TextEditor
    KF6::WidgetsAddons
)

set_target_properties(katetranslucentbarsplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/kf6/ktexteditor"
    PREFIX ""
)

install(TARGETS katetranslucentbarsplugin
    LIBRARY DESTINATION lib/qt6/plugins/kf6/ktexteditor
)
