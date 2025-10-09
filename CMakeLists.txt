cmake_minimum_required(VERSION 3.23)
set (CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH};${CMAKE_SOURCE_DIR}/../yantra")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin")

set(YANTRACC "./ycc")

include(yantra)

project(lingo)
add_yantra("${CMAKE_CURRENT_SOURCE_DIR}/lingo_grammar.y")

add_executable(lingo
    ${CMAKE_CURRENT_BINARY_DIR}/lingo_grammar.cpp
)

target_include_directories (lingo PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}
)
