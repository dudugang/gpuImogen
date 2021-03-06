#include "stdio.h"

#include "mpi.h"
#include "mex.h"

#include "mpi_common.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{

	if((nrhs != 1) || (nlhs != 1)) {
		mexErrMsgTxt("Require topology structure on RHS");
	}

	ParallelTopology topo;
	topoStructureToC(prhs[0], &topo);

	topo.comm = MPI_Comm_c2f(MPI_COMM_WORLD);

	topoCreateDimensionalCommunicators(&topo);
	topoCToStructure(&topo, plhs);

	return;
}
