cmake_minimum_required(VERSION 3.23)
set (CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH};${CMAKE_SOURCE_DIR}/../yantra")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin")

set(BLDPFX "")
if(WIN32)
    set(BLDPFX "win")
elseif(APPLE)
    set(BLDPFX "osx")
elseif(UNIX)
    set(BLDPFX "lin")
endif()

if(NOT DEFINED YANTRACC)
    set(YANTRACC "./ycc")
    if(NOT (EXISTS "${YANTRACC}" AND IS_EXECUTABLE "${YANTRACC}"))
        set(YANTRACC "${CMAKE_BINARY_DIR}/../../../yantra/build/${BLDPFX}-${CMAKE_BUILD_TYPE}/bin/ycc")
        cmake_path(SET YANTRACC NORMALIZE "${YANTRACC}")
        if(NOT (EXISTS "${YANTRACC}" AND IS_EXECUTABLE "${YANTRACC}"))
            message(FATAL_ERROR "Could not find yantracc executable: ${YANTRACC}")
        endif()
    endif()
endif()

message("YANTRACC: ${YANTRACC}")
include(yantra)

project(lingo)
add_yantra("${CMAKE_CURRENT_SOURCE_DIR}/lingo_grammar.y")

add_executable(lingo
    ${CMAKE_CURRENT_BINARY_DIR}/lingo_grammar.cpp
)

target_include_directories (lingo PRIVATE
    ${CMAKE_CURRENT_BINARY_DIR}
)
