#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#ifdef UNIX
#include <stdint.h>
#include <unistd.h>
#endif
#include "mex.h"
#include "mpi.h"

// CUDA
#include "cuda.h"
#include "cuda_runtime.h"
#include "cublas.h"
#include "cudaCommon.h"
#include "parallel_halo_arrays.h"

/* X halo routines */
/* These are the suck; We have to grab 24-byte wide chunks en masse */
/* Fork ny by nz threads to do the job */
__global__ void cukern_HaloXToLinearL(double *mainarray, double *linarray, int nx);
__global__ void cukern_LinearToHaloXL(double *mainarray, double *linarray, int nx);
__global__ void cukern_HaloXToLinearR(double *mainarray, double *linarray, int nx);
__global__ void cukern_LinearToHaloXR(double *mainarray, double *linarray, int nx);

/* Y halo routines */
/* We grab an X-Z plane, making it easy to copy N linear strips of memory */
/* Fork off nz by 3 blocks to do the job */
__global__ void cukern_HaloYToLinearL(double *mainarray, double *linarray, int nx);
__global__ void cukern_LinearToHaloYL(double *mainarray, double *linarray, int nx);
__global__ void cukern_HaloYToLinearR(double *mainarray, double *linarray, int nx, int nz);
__global__ void cukern_LinearToHaloYR(double *mainarray, double *linarray, int nx, int nz);

/* Z halo routines */
/* The easiest; We make one copy of an Nx by Ny by 3 slab of memory */
/* No kernels necessary, we can simply memcpy our hearts out */

pParallelTopology topoStructureToC(const mxArray *prhs);

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
/* Functional form:
    cudaHaloExchange(arraytag, [orientation 3x1], dimension_to_exchange)

    1. get neighbors from halo library in dimension_to_exchange direction
    2. determine which memory direction that currently is
    3. If it's x or y, rip it to a linear array
    4. Aquire some host-pinned memory and dump to that
    5. pass that host pointer to halo_exchange
    6. wait for MPI to return control
*/
  if (nrhs!=4) mexErrMsgTxt("call form is cudaHaloExchange(arraytag, [3x1 orientation], dimension_to_xchg, topology\n");
  if(mxGetNumberOfElements(prhs[1]) != 3) mexErrMsgTxt("2nd argument must be a 3-element array\n");

  ArrayMetadata amd;
  double **array = getGPUSourcePointers(prhs, &amd, 0,0);

  int xchg = (int)*mxGetPr(prhs[2]) - 1;
  int orient[3];

  int ctr;
  for(ctr = 0; ctr < 3; ctr++) { orient[ctr] = (int)*(mxGetPr(prhs[1]) + ctr); }
//printf("orient: %i %i %i\n", orient[0], orient[1], orient[2]); fflush(stdout);

  int memDimension = orient[xchg]-1; // The actual in-memory direction we're gonna be exchanging
 
  // get # of transverse elements, *3 deep for halo
  int numToExchange = 3 * amd.numel / amd.dim[memDimension];
//printf("numel: %i, dim[dimension]: %i; #2xchg: %i\n", amd.numel, amd.dim[memDimension], numToExchange);

  cudaError_t fail = cudaGetLastError(); // Clear the error register
  double *pinnedMem[4];
  double *devPMptr[4];

  pParallelTopology parallelTopo = topoStructureToC(prhs[3]);

  if(xchg+1 > parallelTopo->ndim) return; // The topology does not extend in this dimension
  if(parallelTopo->nproc[xchg] == 1) return; // Only 1 block in this direction.

  for(ctr = 0; ctr < 4; ctr++) {
    fail = cudaHostAlloc(&pinnedMem[ctr], numToExchange * sizeof(double), cudaHostAllocDefault);
    if(fail != cudaSuccess) break;
    fail = cudaHostGetDevicePointer((void **)&devPMptr[ctr], (void *)pinnedMem[ctr], 0);
    }

  if(fail != cudaSuccess) { dim3 f; cudaLaunchError(fail, f, f, &amd, ctr, "cudaHaloExchange.malloc"); }

//pParallelTopology pt = parallelTopo;
//printf("Topology dump by rank %i: ndim=%i, comm=%i\n", (int)*mxGetPr(prhs[4]), pt->ndim, pt->comm);
//printf("left: %i %i\n right: %i %i\n", pt->neighbor_left[0], pt->neighbor_left[1], pt->neighbor_right[0], pt->neighbor_right[1]);
//printf("procs: %i %i\n", pt->nproc[0], pt->nproc[1]);
//fflush(stdout);

  switch(memDimension) {
    case 0: { /* X halo arrangement */
//printf("X halo exchange in progress\n"); fflush(stdout);
      dim3 gridsize; gridsize.x = amd.dim[1]; gridsize.y = amd.dim[2]; gridsize.z = 1;
      dim3 blocksize; blocksize.x = 3; blocksize.y = 1; blocksize.z = 1; // This is horrible.

      cukern_HaloXToLinearL<<<gridsize, blocksize>>>(array[0], devPMptr[0], amd.dim[0]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.X_left_read");
      cukern_HaloXToLinearR<<<gridsize, blocksize>>>(array[0], devPMptr[1], amd.dim[0]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.X_right_read");

//printf("Left halo tx contents: "); int j; for(j = 0; j < numToExchange; j++) { printf("%i ", (int)pinnedMem[0][j]); }
//printf("\nRight halo tx content: "); for(j = 0; j < numToExchange; j++) { printf("%i ", (int)pinnedMem[1][j]); }
//printf("\n");
      cudaDeviceSynchronize(); 
      Parallel_Exchange_Dim_Contig(parallelTopo, 0, pinnedMem[0], pinnedMem[1], pinnedMem[3], pinnedMem[2], numToExchange, MPI_DOUBLE);

//printf("Left halo rx contents: ");   for(j = 0; j < numToExchange; j++) { printf("%i ", (int)pinnedMem[2][j]); }
//printf("\nRight halo rx content: "); for(j = 0; j < numToExchange; j++) { printf("%i ", (int)pinnedMem[3][j]); }
//printf("\n");


      cukern_LinearToHaloXL<<<gridsize, blocksize>>>(array[0], devPMptr[2], amd.dim[0]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.X_left_write");
      cukern_LinearToHaloXR<<<gridsize, blocksize>>>(array[0], devPMptr[3], amd.dim[0]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.X_right_write");
      }; break;

    case 1: { /* Y halo arrangement */
//printf("Y halo exchange in progress\n"); fflush(stdout);
      dim3 blocksize; blocksize.x = 256; blocksize.y = 1; blocksize.z = 1;
      dim3 gridsize; gridsize.x = amd.dim[0]/256; gridsize.y = amd.dim[1]; gridsize.z = 1;
      gridsize.x += gridsize.x*256 < amd.dim[0] ? 1 : 0;

      cukern_HaloYToLinearL<<<gridsize, blocksize>>>(array[0], devPMptr[0], amd.dim[0]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Y_left_read");
      cukern_HaloYToLinearR<<<gridsize, blocksize>>>(array[0], devPMptr[1], amd.dim[0], amd.dim[2]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Y_right_read");

      cudaDeviceSynchronize();
      Parallel_Exchange_Dim_Contig(parallelTopo, 1, pinnedMem[0], pinnedMem[1], pinnedMem[3], pinnedMem[2], numToExchange, MPI_DOUBLE);

      cukern_LinearToHaloYL<<<gridsize, blocksize>>>(array[0], devPMptr[2], amd.dim[0]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Y_left_write");
      cukern_LinearToHaloYR<<<gridsize, blocksize>>>(array[0], devPMptr[3], amd.dim[0], amd.dim[2]);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Y_right_write");
      }; break;

    case 2: { /* Z halo arrangement */
//printf("Z halo exchange in progress\n"); fflush(stdout);
      dim3 gridsize, blocksize;
      cudaMemcpy(pinnedMem[0], array[0], numToExchange*sizeof(double), cudaMemcpyDeviceToHost);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Z_left_readmemcpy");
      cudaMemcpy(pinnedMem[1], &array[0][amd.numel - numToExchange], numToExchange*sizeof(double), cudaMemcpyDeviceToHost);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Z_right_readmemcpy");

      cudaDeviceSynchronize();
      Parallel_Exchange_Dim_Contig(parallelTopo, 2, pinnedMem[0], pinnedMem[1], pinnedMem[3], pinnedMem[2], numToExchange, MPI_DOUBLE);

      cudaMemcpy(array[0], pinnedMem[2], numToExchange*sizeof(double), cudaMemcpyHostToDevice);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Z_left_writememcpy");
      cudaMemcpy(&array[0][amd.numel - numToExchange], pinnedMem[3], numToExchange*sizeof(double), cudaMemcpyDeviceToHost);
      if(fail != cudaSuccess) cudaLaunchError(fail, gridsize, blocksize, &amd, 0, "cudaHaloExchange.Z_right_writememcpy");
      }; break;
    }

  for(ctr = 0; ctr < 4; ctr++)
    cudaFreeHost(pinnedMem[ctr]);

cudaError_t epicFail = cudaDeviceSynchronize();
if(epicFail != cudaSuccess) cudaLaunchError(epicFail, 256, 128, &amd, memDimension, "halo exchange");


free(parallelTopo);

}


/* X halo routines */
/* These are the suck; We have to grab 24-byte wide chunks en masse */
/* Fork ny by nz threads to do the job */
/* We trust the optimizing compiler to clean up the first two lines of sanity-maintainence for us */

/* Copies mainarray(3:5,:,:) to linarray, indexed from 0 */
__global__ void cukern_HaloXToLinearL(double *mainarray, double *linarray, int nx)
{
int myx = threadIdx.x; int myy = blockIdx.x; int myz = blockIdx.y;
int ny = gridDim.x;

int addr = (myx + 3) + (myy + myz*ny)*nx;
int linAddr = myx + 3*(myy + ny*myz);

linarray[linAddr] = mainarray[addr];
}

/* Copies mainarray( (nx-6):(nx-4), :,:) to linarray, indexed from 0 */
__global__ void cukern_HaloXToLinearR(double *mainarray, double *linarray, int nx)
{
int myx = threadIdx.x; int myy = blockIdx.x; int myz = blockIdx.y;
int ny = gridDim.x; 

int addr = (nx - 6 + myx) + (myy + myz*ny)*nx;
int linAddr = myx + 3*(myy + ny * myz);

linarray[linAddr] = mainarray[addr];
}

/* Copies linarray to mainarray(0:2,:,:) */
__global__ void cukern_LinearToHaloXL(double *mainarray, double *linarray, int nx)
{
int myx = threadIdx.x; int myy = blockIdx.x; int myz = blockIdx.y;
int ny = gridDim.x;

int addr = (myx) + (myy + myz*ny)*nx;
int linAddr = myx + 3*(myy + ny * myz);

mainarray[addr] = linarray[linAddr];
}

/* Copies linarray to mainarray((nx-3):(nx-1),:,:) */
__global__ void cukern_LinearToHaloXR(double *mainarray, double *linarray, int nx)
{
int myx = threadIdx.x; int myy = blockIdx.x; int myz = blockIdx.y;
int ny = gridDim.x;


int addr = (nx - 3 + myx) + (myy + myz*ny)*nx;
int linAddr = myx + 3*(myy + ny * myz);

mainarray[addr] = linarray[linAddr];
}

/* Y halo routines */
/* We grab an X-Z plane, making it easy to copy N linear strips of memory */
/* Fork off nz by 3 blocks to do the job */

/* Fork enough threads to cover the X direction , and ny blocks in the y dir  */
__global__ void cukern_HaloYToLinearL(double *mainarray, double *linarray, int nx)
{
int myx = threadIdx.x + blockDim.x * blockIdx.x;
int myy = blockIdx.y;
int ny = gridDim.y;

if(myx >= nx) return;

int addr = myx + nx*myy + 3*nx*ny;
int linAddr = myx + nx*myy;

int ctz;
for(ctz = 0; ctz < 3; ctz++) {
  linarray[linAddr] = mainarray[addr];
  addr += nx*ny;
  linAddr += nx*ny;
  }


}

__global__ void cukern_LinearToHaloYL(double *mainarray, double *linarray, int nx)
{
int myx = threadIdx.x + blockDim.x * blockIdx.x;
int myy = blockIdx.y;
int ny = gridDim.y;

if(myx >= nx) return; 

int addr = myx + nx*myy;
int linAddr = myx + nx*myy;

int ctz;
for(ctz = 0; ctz < 3; ctz++) {
  mainarray[addr] = linarray[linAddr];
  addr += nx*ny;
  linAddr += nx*ny;
  }

}

__global__ void cukern_HaloYToLinearR(double *mainarray, double *linarray, int nx, int nz)
{
int myx = threadIdx.x + blockDim.x * blockIdx.x;
int myy = blockIdx.y;
int ny = gridDim.y;

if(myx >= nx) return; 

int addr = myx + nx*myy + (nz-6)*nx*ny;
int linAddr = myx + nx*myy;

int ctz;
for(ctz = 0; ctz < 3; ctz++) {
  linarray[linAddr] = mainarray[addr];
  addr += nx*ny;
  linAddr += nx*ny;
  }


}

__global__ void cukern_LinearToHaloYR(double *mainarray, double *linarray, int nx, int nz)
{
int myx = threadIdx.x + blockDim.x * blockIdx.x;
int myy = blockIdx.y;
int ny = gridDim.y;

if(myx >= nx) return; 

int addr = myx + nx*myy + (nz-3)*nx*ny;
int linAddr = myx + nx*myy;

int ctz;
for(ctz = 0; ctz < 3; ctz++) {
  mainarray[addr] = linarray[linAddr];
  addr += nx*ny;
  linAddr += nx*ny;
  }

}

pParallelTopology topoStructureToC(const mxArray *prhs)
{

mxArray *a;

pParallelTopology pt = (pParallelTopology)malloc(sizeof(ParallelTopology));

a = mxGetFieldByNumber(prhs,0,0);
pt->ndim = (int)*mxGetPr(a);
a = mxGetFieldByNumber(prhs,0,1);
pt->comm = (int)*mxGetPr(a);

int *val;
int i;

val = (int *)mxGetData(mxGetFieldByNumber(prhs,0,2));
for(i = 0; i < pt->ndim; i++) pt->neighbor_left[i] = val[i];

val = (int *)mxGetData(mxGetFieldByNumber(prhs,0,3));
for(i = 0; i < pt->ndim; i++) pt->neighbor_right[i] = val[i];

val = (int *)mxGetData(mxGetFieldByNumber(prhs,0,4));
for(i = 0; i < pt->ndim; i++) pt->nproc[i] = val[i];

return pt;

   /** Set neighbor_left array
    
   mlIntArray = mxCreateNumericArray(2, dims, mxINT32_CLASS, 0);
   iData = (int *) mxGetData(mlIntArray);
   for (i = 0; i < ndim; i++) {
      iData[i] = aTopology.neighbor_left[i];
   }
   mxSetFieldByNumber(mlTopology, 0, 2, mlIntArray);

   * Set neighbor_right array
    
   mlIntArray = mxCreateNumericArray(2, dims, mxINT32_CLASS, 0);
   iData = (int *) mxGetData(mlIntArray);
   for (i = 0; i < ndim; i++) {
      iData[i] = aTopology.neighbor_right[i];
   }
   mxSetFieldByNumber(mlTopology, 0, 3, mlIntArray);

   * Set nproc array
    
   mlIntArray = mxCreateNumericArray(2, dims, mxINT32_CLASS, 0);
   iData = (int *) mxGetData(mlIntArray);
   for (i = 0; i < ndim; i++) {
      iData[i] = aTopology.nproc[i];
   }
   mxSetFieldByNumber(mlTopology, 0, 4, mlIntArray);
*/
}
