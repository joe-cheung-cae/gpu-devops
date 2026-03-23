cmake_minimum_required(VERSION 3.24)
project(cuda_smoke LANGUAGES CXX CUDA)

set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

add_executable(cuda-smoke main.cu)
