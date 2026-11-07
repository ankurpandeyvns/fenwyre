cmake_minimum_required(VERSION 3.20)
project(blurbehind LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
find_package(Qt6 REQUIRED COMPONENTS Quick)
find_package(KF6WindowSystem REQUIRED)
qt_standard_project_setup(REQUIRES 6.5)
qt_add_qml_module(blurbehind URI net.local.blur VERSION 1.0 PLUGIN_TARGET blurbehind SOURCES blurbehind.h blurbehind.cpp
                  OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/net/local/blur)
target_link_libraries(blurbehind PRIVATE Qt6::Quick KF6::WindowSystem)
