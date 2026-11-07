cmake_minimum_required(VERSION 3.20)
project(lockwatch LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
find_package(Qt6 REQUIRED COMPONENTS Qml DBus)
qt_standard_project_setup(REQUIRES 6.5)
qt_add_qml_module(lockwatch URI net.local.lockwatch VERSION 1.0 PLUGIN_TARGET lockwatch SOURCES lockwatcher.h lockwatcher.cpp
                  OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/net/local/lockwatch)
target_link_libraries(lockwatch PRIVATE Qt6::Qml Qt6::DBus)
