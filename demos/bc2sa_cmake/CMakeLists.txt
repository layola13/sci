cmake_minimum_required(VERSION 3.16)

project(bc2sa_cmake_demo C)

find_program(CLANG_EXE clang REQUIRED)

set(SAMPLE_C ${CMAKE_CURRENT_SOURCE_DIR}/main.c)
set(SAMPLE_BC ${CMAKE_CURRENT_BINARY_DIR}/main.bc)

add_custom_command(
    OUTPUT ${SAMPLE_BC}
    COMMAND ${CLANG_EXE} -std=c11 -O0 -emit-llvm -c ${SAMPLE_C} -o ${SAMPLE_BC}
    DEPENDS ${SAMPLE_C}
    COMMENT "Building LLVM bitcode main.bc"
    VERBATIM
)

add_custom_target(bc ALL DEPENDS ${SAMPLE_BC})
