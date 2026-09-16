cmake_minimum_required(VERSION 3.24)
project(wechat-glass-live VERSION 0.5.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
find_package(ECM REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Quick DBus)
find_package(KWin REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(XCB REQUIRED IMPORTED_TARGET xcb)
set(EFFECT_ID wechat-glass-live-v5)
add_library(${EFFECT_ID} MODULE glass.cpp shaders.qrc)
set_target_properties(${EFFECT_ID} PROPERTIES
    PREFIX ""
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plugins/kwin/effects/plugins"
)
target_link_libraries(${EFFECT_ID} PRIVATE KWin::kwin PkgConfig::XCB)
target_compile_options(${EFFECT_ID} PRIVATE -Wall -Wextra)
install(TARGETS ${EFFECT_ID} LIBRARY DESTINATION lib/qt6/plugins/kwin/effects/plugins)

option(WECHAT_GLASS_BUILD_TESTS "Build the isolated KWin regression test client" OFF)
if(WECHAT_GLASS_BUILD_TESTS)
    enable_testing()
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    add_executable(wechat-glass-test-client tests/corner-test.cpp)
    target_link_libraries(wechat-glass-test-client PRIVATE Qt6::Widgets)
    set_target_properties(wechat-glass-test-client PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests"
    )
    add_test(NAME corners-and-live-updates
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test-corners.py)
    add_test(NAME transparency-during-close
        COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test-closing.py)
    foreach(scale IN ITEMS 1.0 1.25)
        add_test(NAME edges-at-${scale}
            COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test-edges.py)
        set_tests_properties(edges-at-${scale} PROPERTIES
            ENVIRONMENT "WECHAT_GLASS_BUILD_DIR=${CMAKE_BINARY_DIR};WECHAT_GLASS_TEST_SCALE=${scale}"
            TIMEOUT 90
        )
    endforeach()
    set_tests_properties(corners-and-live-updates transparency-during-close PROPERTIES
        ENVIRONMENT "WECHAT_GLASS_BUILD_DIR=${CMAKE_BINARY_DIR}"
        TIMEOUT 90
    )
endif()
