#include "stdio.h"

#include "mpi.h"
#include "mex.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
   MPI_Finalize();
}
