
#include "mex.h"
#include "cudaCommon.h"
#include "compiled_common.h"
#include "cudaFluidStep.h"
#include "cudaArrayRotateB.h"
#include "cudaHaloExchange.h"
#include "cudaStatics.h"

#include "flux.h"


int setFluidBoundaries(MGArray *x, int nArrays, int dir);

int performFluidUpdate_3D(MGArray *fluid, pParallelTopology parallelTopo, int order, int stepNumber, double *lambda, double gamma, double stepMethod)
{
int sweep;

// Choose our sweep number depending on whether we are 1- or 2-dimensional
if(fluid[0].dim[2] > 1) {
	sweep = (stepNumber - 1 + 3*(order > 0)) % 6;
} else {
	sweep = (stepNumber + 1 + (order < 0)) % 2;
}

int preperm[6] = {0, 2, 0, 2, 3, 3};

int fluxcall[3][6] = {{1,2,1,2,3,3},{3,1,2,3,1,2},{2,3,3,1,2,1}};
int permcall[3][6] = {{3,2,2,3,3,2},{2,3,3,5,2,6},{6,3,5,0,2,0}};

int n;
int returnCode = SUCCESSFUL;
int nowDir;

FluidStepParams stepParameters;
stepParameters.onlyHydro = 1;
stepParameters.thermoGamma = gamma;
stepParameters.minimumRho = 1e-8; // FIXME HAX HAX HAX
stepParameters.stepMethod = stepMethod;

if(order > 0) { /* If we are doing forward sweep */
	returnCode = (preperm[sweep] != 0 ? flipArrayIndices(fluid, NULL, 5, preperm[sweep]) : SUCCESSFUL);
	if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);

	for(n = 0; n < 3; n++) {
		nowDir = fluxcall[n][sweep];
		if(fluid->dim[nowDir-1] > 3) {
			stepParameters.lambda = lambda[nowDir-1];
			stepParameters.stepDirection = nowDir;

			returnCode = performFluidUpdate_1D(fluid, stepParameters);
			if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
			returnCode = setFluidBoundaries(fluid, 5, nowDir);
			if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
			returnCode = exchange_MPI_Halos(fluid, 5, parallelTopo, nowDir);
			if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
		}
		/* FIXME: INSERT MAGNETIC FLUX ROUTINES HERE */

		returnCode = (permcall[n][sweep] != 0 ? flipArrayIndices(fluid, NULL, 5, permcall[n][sweep]) : SUCCESSFUL );
		if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
	}

} else { /* If we are doing backwards sweep */
	returnCode = (preperm[sweep] != 0 ? flipArrayIndices(fluid, NULL, 5, preperm[sweep]) : SUCCESSFUL);
	if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);

	for(n = 0; n < 3; n++) {
		nowDir = fluxcall[n][sweep];
		/* FIXME: INSERT MAGNETIC FLUX ROUTINES HERE */

		if(fluid->dim[nowDir-1] > 3) {
			stepParameters.lambda = lambda[nowDir-1];
			stepParameters.stepDirection = nowDir;

			returnCode = performFluidUpdate_1D(fluid, stepParameters);
			if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
			returnCode = setFluidBoundaries(fluid, 5, nowDir);
			if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
			returnCode = exchange_MPI_Halos(fluid, 5, parallelTopo, nowDir);
			if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
		}

		returnCode = (permcall[n][sweep] != 0 ? flipArrayIndices(fluid, NULL, 5, permcall[n][sweep]) : SUCCESSFUL );
		if(returnCode != SUCCESSFUL) return CHECK_IMOGEN_ERROR(returnCode);
	}
}

return CHECK_IMOGEN_ERROR(returnCode);

/* Fluid half-step completed 
 * If order > 0, next call sourcing terms
 * If order < 0, next call fluid with order > 0 */
}

int setFluidBoundaries(MGArray *x, int nArrays, int dir)
{
	int i;
	for(i = 0; i < nArrays; i++) {
		setBoundaryConditions(x[i].matlabClassHandle, dir);
	}
	return SUCCESSFUL;

}

