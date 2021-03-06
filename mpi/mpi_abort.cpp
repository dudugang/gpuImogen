#include "stdio.h"

#include "mpi.h"
#include "mex.h"
#include "matrix.h"

/*#include "mpi_common.h" */
using namespace std;

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
MPI_Comm commune = MPI_COMM_WORLD;

int d = -1;

if(nrhs > 0) {
	double *f = mxGetPr(prhs[0]);
	if(f != NULL) d = (int)f[0];
}

MPI_Abort(commune, d);

}

