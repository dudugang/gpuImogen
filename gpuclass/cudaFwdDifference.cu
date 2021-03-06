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

/* THIS FUNCTION
   Calculates

   array(R) += lambda*(flux(R + i) - flux(R))

   where R = (xi, yi, zi) indexes any given cell, 
   i = ( (direction == 1), (direction == 2), (direction == 3) ),
   and lambda is a real scalar.

   That is, it adds lambda * the flux gradient to array where the flux
   gradient is calculated using the forward difference f' = f(x+1)-f(x)
*/

__global__ void cukern_ForwardDifferenceX(double *array, double *flux, int nx, double lambda);
__global__ void cukern_ForwardDifferenceY(double *array, double *flux, int nx, int ny, double lambda);
__global__ void cukern_ForwardDifferenceZ(double *array, double *flux, int nx, int nz, double lambda);

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
    if ((nrhs != 4) || (nlhs != 0)) {
        mexErrMsgTxt("Arguments must be cudaFwdDifference(array, flux, direction, flux factor)\n");
        }

  CHECK_CUDA_ERROR("entering cudaFwdDifference");

    // Get source array info and create destination arrays
    MGArray src[2];
    int worked = MGA_accessMatlabArrays(prhs, 0, 1, src);

    // Establish launch dimensions & a few other parameters
    int direction = (int)*mxGetPr(prhs[2]);
    double lambda = *mxGetPr(prhs[3]);

    dim3 arraySize = makeDim3(&src->dim[0]);

    dim3 blocksize, gridsize;
    blocksize.z = 1;
    gridsize.z = 1;

    cudaSetDevice(src->deviceID[0]);
    CHECK_CUDA_ERROR("cudaSetDevice()");

    // Interpolate the grid-aligned velocity
    switch(direction) {
        case 1:
            blocksize = makeDim3(128, 1, 1);
            gridsize.x = arraySize.y; gridsize.y = arraySize.z;
            cukern_ForwardDifferenceX<<<gridsize, blocksize>>>(src[0].devicePtr[0], src[1].devicePtr[0], arraySize.x, lambda);
            break;
        case 2:
            blocksize = makeDim3(64,1,1);
            gridsize.x = arraySize.x / 64; gridsize.x += (64*gridsize.x < arraySize.x);
            gridsize.y = arraySize.z;
            cukern_ForwardDifferenceY<<<gridsize, blocksize>>>(src[0].devicePtr[0], src[1].devicePtr[0], arraySize.x, arraySize.y, lambda);
            break;
        case 3:
            blocksize = makeDim3(64,1,1);
            gridsize.x = arraySize.x / 64; gridsize.x += (64*gridsize.x < arraySize.x);
            gridsize.y = arraySize.y;
            cukern_ForwardDifferenceZ<<<gridsize, blocksize>>>(src[0].devicePtr[0], src[1].devicePtr[0], arraySize.x, arraySize.z, lambda);
            break;
        }

    CHECK_CUDA_LAUNCH_ERROR(blocksize, gridsize, src, direction, "Backwards averaging");

}

/*
Invoke with a grid for which blockdim.x = size(array, Y) and blockdim.y = size(array,Z);
with 128 threads in the X direction.
*/
__global__ void cukern_ForwardDifferenceX(double *array, double *flux, int nx, double lambda)
{
int yAddr = blockIdx.x;
int zAddr = blockIdx.y;
int ny = gridDim.x;

int addrMax = nx*(yAddr + ny*zAddr + 1); // The address which we must not reach or go beyond is the start of the next line
int readBase = threadIdx.x + nx*(yAddr + ny*zAddr);
int writeBase= readBase;
readBase -= nx*(readBase >= addrMax);

__shared__ double lStore[256];

int locAddr = threadIdx.x;

//lStore[locAddr] = in[globBase + readX]; // load the first memory segment
lStore[locAddr] = flux[readBase]; // load the first memory segment

do {
    readBase += 128;
    readBase -= nx*(readBase >= addrMax);
    lStore[(locAddr + 128) % 256] = flux[readBase];

    __syncthreads(); // We have now read ahead by a segment. Calculate forward average, comrades!

    if(writeBase < addrMax) { array[writeBase] += lambda*(lStore[(locAddr+1)%256] - lStore[locAddr]); } // If we are within range, that is.
    writeBase += 128; // Advance write address
    if(writeBase >= addrMax) return; // If write address is beyond nx, we're finished.
    locAddr ^= 128;

    __syncthreads();

    } while(1);

}

/* Invoke with a blockdim of <64, 1, 1> threads
Invoke with a griddim = <ceil[nx / 64], nz, 1> */
__global__ void cukern_ForwardDifferenceY(double *array, double *flux, int nx, int ny, double lambda)
{
int xaddr = blockDim.x * blockIdx.x + threadIdx.x; // There are however many X threads
if(xaddr >= nx) return; // truncate this right off

__shared__ double tileA[64];
__shared__ double tileB[64];

double *setA = tileA;
double *setB = tileB;
double *swap;

int readBase = xaddr + nx*ny*blockIdx.y; // set Raddr to x + nx ny z
int writeBase = readBase;
int addrMax = readBase + nx*(ny - 1); // Set this to the max address we want to handle in the loop

setB[threadIdx.x] = flux[readBase]; // load set B (e.g. row 0)

while(writeBase < addrMax) { // Exit one BEFORE the max address to handle (since the max is a special case)
    swap = setB; // exchange A/B pointers
    setB = setA;
    setA = swap; // swap so that row 0 is set A
    
//    __syncthreads();

    readBase += nx; // move pointer down one row
    setB[threadIdx.x] = flux[readBase]; // load row 1 into set B

//    __syncthreads();

    array[writeBase] += lambda*(setB[threadIdx.x] - setA[threadIdx.x]); // average written to output

    writeBase += nx;
    }

readBase = xaddr + nx*ny*blockIdx.y; // reset readbase
setA[threadIdx.x] = flux[readBase];
// Note that this is reversed because we did not flip the setA/setB pointers for the last row.
array[writeBase] += lambda*(setA[threadIdx.x] - setB[threadIdx.x]); // average written to output

}

/* Invoke with a blockdim of <64, 1, 1> threads
Invoke with a griddim = <ceil[nx / 64], ny, 1> */
__global__ void cukern_ForwardDifferenceZ(double *array, double *flux, int nx, int nz, double lambda)
{
int xaddr = blockDim.x * blockIdx.x + threadIdx.x; // There are however magridDim.y X threads
if(xaddr >= nx) return; // truncate this right off

__shared__ double tileA[64];
__shared__ double tileB[64];

double *setA = tileA;
double *setB = tileB;
double *swap;

int readBase = xaddr + nx*blockIdx.y; // set Raddr to x + nx gridDim.y z
int writeBase = readBase;
int addrMax = readBase + nx*gridDim.y*(nz - 1); // Set this to the max address we want to handle in the loop

setB[threadIdx.x] = flux[readBase]; // load set B (e.g. row 0)

while(writeBase < addrMax) { // Exit one BEFORE the max address to handle (since the max is a special case)
    swap = setB; // exchange A/B pointers
    setB = setA;
    setA = swap; // swap so that row 0 is set A

//    __syncthreads();

    readBase += nx*gridDim.y; // move pointer down one row
    setB[threadIdx.x] = flux[readBase]; // load row 1 into set B

//    __syncthreads();

    array[writeBase] += lambda*(setB[threadIdx.x] - setA[threadIdx.x]); // average written to output

    writeBase += nx*gridDim.y;
    }

readBase = xaddr + nx*blockIdx.y; // reset readbase
setA[threadIdx.x] = flux[readBase];
// Note that this is reversed because we did not exchange the setA/setB pointers.
array[writeBase] += lambda*(setA[threadIdx.x] - setB[threadIdx.x]); // average written to output

}

