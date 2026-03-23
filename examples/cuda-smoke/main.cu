#include <cuda_runtime.h>

#include <iostream>

__global__ void nop_kernel() {}

int main() {
  nop_kernel<<<1, 1>>>();
  cudaError_t result = cudaDeviceSynchronize();
  if (result != cudaSuccess) {
    std::cerr << "CUDA execution failed: " << cudaGetErrorString(result) << '\n';
    return 1;
  }

  std::cout << "CUDA smoke test passed" << '\n';
  return 0;
}
