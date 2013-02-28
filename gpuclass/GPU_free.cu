#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#ifdef UNIX
#include <stdint.h>
#include <unistd.h>
#endif
#include "mex.h"

// CUDA
#include "cuda.h"
#include "cuda_runtime.h"
#include "cublas.h"

#include "cudaCommon.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
  // wrapper for cudaFree().
  if((nlhs != 0) || (nrhs != 1)) mexErrMsgTxt("GPU_free: syntax is GPU_free(GPU_MemPtr object)");

  if(mxGetClassID(prhs[0]) != mxINT64_CLASS) mexErrMsgTxt("GPU_free: pass a not-gpupointer");

  int64_t *t = (int64_t *)mxGetData(prhs[0]);

  double *d = (double *)t[0];

  cudaCheckError("Before GPU_free()");
  cudaError_t result = cudaFree(d);
  cudaCheckError("After GPU_free()");

  return;
}
