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

/* THIS FUNCTION
   Applies the effects of a star (or other compact body) undergoing active accretion. This
   takes the form of (1) Matter being "vacuumed" off the grid and being accumulated onto the
   object and (2) The compact object applying a central gravitational force to the grid.

   The "compact" object is considered as having a radius (the point at which its local
   gravity makes matters numerically problematic, more likely than a physical value). All
   cells which evaluate as being inside this radius have their mass/energy/momentum added to the
   object's values, while the cells' values are set to non-interacting "false vacuum" values

   The accretion calculation is only invoked if the accretion radius of an object intersects this
   MPI rank's grid section, while all ranks perform the gravitational calculation.
 */
void __global__ cudaStarAccretes(double *rho, double *px, double *py, double *pz, double *E, int3 gridLL, double h, int nx, int ny, int nz, double *stateOut, int ncellsvert);
void __global__ cudaStarGravitation(double *rho, double *px, double *py, double *pz, double *E, int3 arraysize);

__constant__ __device__ double starState[14];
// Need to track star's
// position (3D), momentum (3D), angular momentum (3D), mass (1D), radius (1D), vaccum_rho grav_rho vac_E(3D) = 14 doubles
#define STAR_X      0
#define STAR_Y      1
#define STAR_Z      2
#define STAR_RADIUS 3
#define STAR_PX     4
#define STAR_PY     5
#define STAR_PZ     6
#define STAR_LX     7
#define STAR_LY     8
#define STAR_LZ     9
#define STAR_MASS   10
#define VACUUM_RHO  11
#define VACUUM_RHOG 12
#define VACUUM_E    13

__constant__ __device__ double gravParams[9];
#define GRAVP_GMDT 0
#define GRAVP_X0   1
#define GRAVP_Y0   2
#define GRAVP_Z0   3
#define GRAVP_H    4


#define ACCRETE_NX 8
#define ACCRETE_NY 8

#define GRAVITY_NX 16
#define GRAVITY_NY 16

// FIXME: NOTE: The below can be implemented but unless we need to again I see no reason to actually do that.

// Define: F = -beta * rho * grad(phi)
// rho_g = density for full effect of gravity 
// rho_c = minimum density to feel gravity at all
// beta = { rho_g < rho         : 1                                 }
//        { rho_c < rho < rho_g : [(rho-rho_c)/(rho_rho_g-rho_c)]^2 }
//        {         rho < rho_c : 0                                 }

// This provides a continuous (though not differentiable at rho = rho_g) way to surpress gravitation of the background fluid
// The original process of cutting gravity off below a critical density a few times the minimum
// density is believed to cause "blowups" at the inner edge of circular flow profiles due to being
// discontinuous. If even smoothness is insufficient and smooth differentiability is required,
// a more-times-continuous profile can be constructed, but let's not go there unless forced.

// Density below which we force gravity effects to zero
#define RHOMIN gravParams[5]
#define RHOGRAV gravParams[6]
// 1 / (rho_g - rho_c)
#define G1 gravParams[7]
// rho_c / (rho_g - rho_c)
#define G2 gravParams[8]

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[]) {
	if ((nrhs != 10) || (nlhs != 1)) mexErrMsgTxt("Wrong number of arguments: need newState = cudaAccretingStar(rho, px, py, pz, E, starState, lower left corner global index, grid size H, dt, topology_size);");

	CHECK_CUDA_ERROR("entering cudaAccretingStar");

	double lowleft[3], upright[3];

	double *i0 = mxGetPr(prhs[6]); // Global lower left index
	double H   = *mxGetPr(prhs[7]); // grid space H
	double dtime = *mxGetPr(prhs[8]); // timestep
	double *topologySize = mxGetPr(prhs[9]); // size of topology (FIXME: Get this from MPI...)

	double *hostStarState = mxGetPr(prhs[5]);
	// Position transform the star into rank-local coordinates by subtracting off our offset coordinate scaled by h.
	double originalStarState[14];
	int j;
	for(j = 0; j < 3; j++) originalStarState[j] = hostStarState[j] - H*i0[3+j];
	for(j = 3; j < 14; j++) originalStarState[j] = hostStarState[j];

	cudaMemcpyToSymbol(starState, &originalStarState[0], 14*sizeof(double), 0, cudaMemcpyHostToDevice);
	CHECK_CUDA_ERROR("Copying star state to __constant__ memory");

	// Get source array info and create destination arrays
	MGArray fluid[5];
	int worked = MGA_accessMatlabArrays(prhs, 0, 4, fluid);

	int is3D = (fluid->dim[2] > 1);

	// FIXME: Implement (or steal from a CSG code) SphereInsideBox()
	// Check if any part of the stellar accretion region is on our grid.
	int mustAccrete = 1;
	for(j = 0; j < 3; j++) {
		lowleft[j] = (i0[j]-1+3*(topologySize[j] > 1) )*H; // Use topologySize to avoid accreting from halo region, which would get doublecounted
		upright[j] = (i0[j]-1+fluid->dim[j]-3*(topologySize[j] > 1))*H;

		if(lowleft[j] > originalStarState[STAR_X+j] + originalStarState[STAR_RADIUS]) mustAccrete = 0; // If our left  > R_star from the star, no accretion
		if(upright[j] < originalStarState[STAR_X+j] - originalStarState[STAR_RADIUS]) mustAccrete = 0; // If our right > R_star from the star, no accretion
	}

	int bee;
	MPI_Comm_rank(MPI_COMM_WORLD, &bee);
	//printf("rank %i: LL=[%g %g %g] *=[%g %g %g] UR=[%g %g %g] mustAccrete=%i", bee, lowleft[0], lowleft[1], lowleft[2], originalStarState[STAR_X+0], originalStarState[STAR_X+1], originalStarState[STAR_X+2], upright[0], upright[1], upright[2], mustAccrete); fflush(stdout);

	// Each rank stores its final accumulated sum here
	double localFinalDelta[7];
	for(j = 0; j < 7; j++) localFinalDelta[j] = 0;
	int nparts = 0;
	double *hostDeltas;

	double *S[5];
	int i;
	for(i = 0; i < 5; i++) S[i] = fluid[i].devicePtr[0];

	// If we've determined that star intersects our grid
	if(mustAccrete) {
		int starRadInCells = originalStarState[STAR_RADIUS] / H + 2;

		dim3 acBlock, acGrid;
		acBlock.x = ACCRETE_NX; acBlock.y = ACCRETE_NY; acBlock.z = 1;
		acGrid.x = 2*starRadInCells/ACCRETE_NX; acGrid.x += (ACCRETE_NX*acGrid.x < 2*starRadInCells);
		acGrid.y = 2*starRadInCells/ACCRETE_NY; acGrid.y += (ACCRETE_NY*acGrid.y < 2*starRadInCells);
		acGrid.z = 1;

		nparts = acGrid.x*ACCRETE_NX*acGrid.y*ACCRETE_NY;
		hostDeltas = (double *)malloc(sizeof(double)*nparts*8);

		double *stateOut;
		cudaError_t fail = cudaMalloc((void **)&stateOut, sizeof(double)*nparts*8);

		// Determine the target region:
		// Makes sure that we don't accrete from the halo zone
		int3 LL;
		LL.x = (int)((originalStarState[0] - originalStarState[3])/H) - 2;
		LL.y = (int)((originalStarState[1] - originalStarState[3])/H) - 2;
		if(is3D) {
			LL.z = (int)((originalStarState[2] - originalStarState[3])/H) - 2;
		} else {
			LL.z = 0;
		}

		//printf("Orig  LL: %i %i %i\n", LL.x, LL.y, LL.z);
		// Force the block to not begin further left than the left part of our fluid domain
		if(LL.x < 3*(topologySize[0] > 1)) LL.x = 3*(topologySize[0] > 1);
		if(LL.y < 3*(topologySize[1] > 1)) LL.y = 3*(topologySize[1] > 1);
		if( (LL.z < 3*(topologySize[2] > 1)) && is3D) LL.z = 3*(topologySize[2] > 1);
		// Also force it to not begin further right
		// We presume that the domain & radius are compatible with the left and right edge conditions not being simultaneously met
		// As might be implied by the phrase "COMPACT object".
		if( (LL.x + acGrid.x*ACCRETE_NX) > (fluid->dim[0]-3*(topologySize[0] > 1)) ) LL.x = fluid->dim[0] - 3*(topologySize[0] > 1) - acGrid.x*ACCRETE_NX;
		if( (LL.y + acGrid.y*ACCRETE_NY) > (fluid->dim[1]-3*(topologySize[1] > 1)) ) LL.y = fluid->dim[1] - 3*(topologySize[1] > 1) - acGrid.y*ACCRETE_NY;
		int nvertical = 2*starRadInCells + 8;
		if(( (LL.z + nvertical) > (fluid->dim[2]-3*(topologySize[2] > 1)) ) && is3D) LL.z = fluid->dim[2] - 3*(topologySize[2] > 1) - nvertical;

		//printf("check LL: %i %i %i\n", LL.x, LL.y, LL.z);
		//printf("check gs: %i %i %i\n", acGrid.x, acGrid.y, acGrid.z);
		//printf("check bs: %i %i %i\n", acBlock.x,acBlock.y,acBlock.z);

		// call accretion kernel: transfers bits of changed state to outputState
		cudaStarAccretes<<<acGrid, acBlock>>>(S[0], S[1], S[2], S[3], S[4], LL, H, fluid->dim[0], fluid->dim[1], fluid->dim[2], stateOut, is3D ? 2*starRadInCells+8 : 1);

		cudaDeviceSynchronize(); // Force accretion to finish.
		CHECK_CUDA_ERROR("just ran cudaStarAccretes()");
		fail = cudaMemcpy((void *)hostDeltas, (void *)stateOut, 8*sizeof(double)*nparts, cudaMemcpyDeviceToHost);
		CHECK_CUDA_ERROR("copying accretion results to host");
		cudaDeviceSynchronize();
		CHECK_CUDA_ERROR("sync after copy start");
		cudaFree(stateOut);
		CHECK_CUDA_ERROR("free stateOut after copy & sync");
	}


	// Produce a single accumulated delta for all ranks,
	// FIXME: We'll give a crap about absorbed angular momentum once we're actually in a position to /do/ something about it.
	if(mustAccrete) {
		int k;
		for(j = 0; j < nparts; j++) {
			for(k = 0; k < 5; k++) { localFinalDelta[k] += hostDeltas[8*j+k]; }
			// localFinalDelta[0 1 2 3 4] = absorbed [mass px py pz E] / dV
		}

		free(hostDeltas);
	}

	// Add up all the changes
	double finalDelta[7];
	int mpi_error = MPI_Allreduce((void *)&localFinalDelta[0], (void *)&finalDelta[0], 5, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);

	// Produce the change we send back for the
	// [X Y Z R Px Py Pz Lx Ly Lz M rhoV, EV]
	mwSize outputdim[2]; outputdim[0] = 1; outputdim[1] =14;
	plhs[0] = mxCreateNumericArray(2, (const mwSize *)&outputdim, mxDOUBLE_CLASS, mxREAL);
	double *outputDelta = mxGetPr(plhs[0]);

	double dv = H*H*H;

	// First we need to calculate the output delta we'll hand back given a full timestep.
	//    <calculate accretion rate here>
	//    [fluid flux]   ^^^  [half accrete] [half star drift] [source grav.pot.] [.5 drift] [.5 accrete] [fluid flux]
	// originalStarState
	// Bear in mind, originalStarState is transformed re:position such that our grid's <0 0 0> index is the coordinate origin.

	// deltaX: evaluate with dt*[P + Pdot*dt/2]/[M + Mdot*dt/2]
	outputDelta[0] = dtime * (originalStarState[STAR_PX] + finalDelta[1]*dv)/(originalStarState[STAR_MASS] + finalDelta[0]*dv);
	outputDelta[1] = dtime * (originalStarState[STAR_PY] + finalDelta[2]*dv)/(originalStarState[STAR_MASS] + finalDelta[0]*dv);
	outputDelta[2] = dtime * (originalStarState[STAR_PZ] + finalDelta[3]*dv)/(originalStarState[STAR_MASS] + finalDelta[0]*dv);
	// delta in radius: 0 pending construction of a more sophisticated model
	outputDelta[3] = 0;
	// delta in momentum
	outputDelta[4] = finalDelta[1]*dv;
	outputDelta[5] = finalDelta[2]*dv;
	outputDelta[6] = finalDelta[3]*dv;
	// delta in angular momentum: don't care
	outputDelta[7] = outputDelta[8] = outputDelta[9] = 0;
	// delta in mass
	outputDelta[10] = finalDelta[0]*dv;
	// delta in "vacuum" density/energy density
	outputDelta[11] = outputDelta[12] = outputDelta[13] = 0;
	// Now we need to calculate the position & mass at halftime so we can go ahead and calculate gravitation on the fluid
	// store parameters in constant memory: G*M*dt, [Xstar Ystar Zstar], H
	double gp[9];
	gp[0] = dtime*(originalStarState[STAR_MASS] + .5*outputDelta[STAR_MASS]);
	gp[1] = originalStarState[STAR_X] + .5*outputDelta[STAR_X];
	gp[2] = originalStarState[STAR_Y] + .5*outputDelta[STAR_Y];
	gp[3] = originalStarState[STAR_Z] + .5*outputDelta[STAR_Z];
	gp[4] = H;
	gp[5] = originalStarState[VACUUM_RHO];
	gp[6] = originalStarState[VACUUM_RHOG];
	gp[7] = 1.0/(originalStarState[VACUUM_RHOG] - originalStarState[VACUUM_RHO]);
	gp[8] = originalStarState[VACUUM_RHO] *gp[7];

	//if(mustAccrete) {
		//  int qq;
	//  printf("copied to gravParams: ");
	//  for(qq = 0; qq < 9; qq++) { printf("%lg ",gp[qq]); }
	//printf("\n");
	//  }
	CHECK_CUDA_ERROR("memcpy to symbol before gravitate");
	cudaMemcpyToSymbol(gravParams, &gp[0], 9*sizeof(double), 0, cudaMemcpyHostToDevice);
	CHECK_CUDA_ERROR("point gravity symbol copy");
	cudaDeviceSynchronize();

	dim3 gravBlock, gravGrid;

	int3 arraysize; arraysize.x = fluid->dim[0]; arraysize.y = fluid->dim[1]; arraysize.z = fluid->dim[2];

	int *dim = &fluid->dim[0];
	dim3 tileDimension(GRAVITY_NX, GRAVITY_NY, 1);
	dim3 gravHalo(0,0,0);
        getTiledLaunchDims(dim, &tileDimension, &gravHalo, &gravBlock, &gravGrid);
	gravGrid.z = 1;

	cudaStarGravitation<<<gravGrid, gravBlock>>>(S[0], S[1], S[2], S[3], S[4], arraysize);
	CHECK_CUDA_ERROR("Ran pointlike gravitation routine");

}


// This occupies a relatively small number of SMs, so we wish to run it concurrently with the point gravitation kernel which everybody does.


// Need to track star's
// position (3D), momentum (3D), angular momentum (3D), mass (1D), radius (1D), vaccum_rhoE(2D) = 13 doubles

// Store [X Y Z R Px Py Pz Lx Ly Lz M rhoV, EV] in full state vector:
//                   Need to read only [X Y Z R] to calc additions
// Calculate differential accumulation of the above which is
//                   Need output only [dP, dL, dM] = 7x1

// Launch with however many threads/blocks are appropriate to cover entire stellar accretion region.
// 
void __global__ cudaStarAccretes(double *rho, double *px, double *py, double *pz, double *E, int3 gridLL, double h, int nx, int ny, int nz, double *stateOut, int ncellsvert)
{
	int myx = threadIdx.x + ACCRETE_NX * blockIdx.x + gridLL.x;
	int myy = threadIdx.y + ACCRETE_NY * blockIdx.y + gridLL.y;
	int myz = gridLL.z;
	int z;

	// Zero my contribution to delta-state
	double dstate[7];
	for(z = 0; z < 7; z++) dstate[z] = 0.0;

	if((myx >= nx) || (myy >= ny)) return;
	int globAddr = myx + nx*(myy + ny*myz);

	// Load stellar state vector
	double starX = starState[STAR_X];
	double starY = starState[STAR_Y];
	double starZ = starState[STAR_Z];
	double starR = starState[STAR_RADIUS];

	double accFactor = 1.0; // If we're at a face/edge/corner then multiple ranks will accrete so reduce appropriately.

	if( (myx < 3) || (myx > (nx-4))) accFactor = .5;
	if( (myy < 3) || (myy > (ny-4))) accFactor *= .5;
	// FIXME: This needs to account for steppign through z. Unroll Z loops and add only half if at edge.
	//if( (myz < 3) || (myz > (nz-4))) accFactor *= .5;

	// We step up columns in the Z direction so the "axial" radius is fixed
	double dXYsqr = (h*myx-starX)*(h*myx-starX) + (h*myy-starY)*(h*myy-starY);
	double dz = h*myz - starZ;
	double q;

	for(z = 0; z < ncellsvert; z++) {
		// Calculate my grid position
		//  if(dz > starR) break; // Quit once we're beyond the accretion sphere
		double rsqr = dXYsqr + dz*dz;

		// Calculate how far it is from the given X of the star
		if(rsqr < starR*starR) {
			//If within, add stuff to local state vector:
			// We'll rescale by h^3 after on the cpu, once.

			// Move the mass to our dmass, set the density back to minimum
			q = rho[globAddr];
			dstate[0] += (q-starState[VACUUM_RHO]);
			rho[globAddr] = starState[VACUUM_RHO];

			// Add dv*mom to Pstar, write zero to mom
			q = px[globAddr]; dstate[1] += q; px[globAddr] = 0;
			q = py[globAddr]; dstate[2] += q; py[globAddr] = 0;
			q = pz[globAddr]; dstate[3] += q; pz[globAddr] = 0;

			// Move dv*(E - vaccuum_E) to star, write vacuum_E to ener
			q = E[globAddr]; dstate[4] += q; E[globAddr] = starState[VACUUM_E];

		}

		globAddr += nx*ny;
		dz += h;
	}

	__syncthreads();

	myx -= gridLL.x;
	myy -= gridLL.y;
	int i0 = (myx + ACCRETE_NX*gridDim.x*myy)*8;

	for(z = 0; z < 7; z++) { stateOut[i0+z] = accFactor * dstate[z]; }

}


//access gravParams[] using:
//define GRAVP_GMDT 0
//define GRAVP_X0   1
//define GRAVP_Y0   2
//define GRAVP_Z0   3
//define GRAVP_H    4
//#define RHOMIN gravParams[5]
//#define RHOGRAV gravParams[6]
// 1 / (rho_g - rho_c)
//#define G1 gravParams[7]
// rho_c / (rho_g - rho_c)
//#define G2 gravParams[8]


void __global__ cudaStarGravitation(double *rho, double *px, double *py, double *pz, double *E, int3 arraysize)
{
	int myx = threadIdx.x + GRAVITY_NX*blockIdx.x;
	int myy = threadIdx.y + GRAVITY_NY*blockIdx.y;

	int globAddr = myx + arraysize.x*myy;

	if((myx >= arraysize.x) || (myy >= arraysize.y)) return;
	double H = gravParams[GRAVP_H];

	double dx = myx*H - gravParams[GRAVP_X0];
	double dy = myy*H - gravParams[GRAVP_Y0];
	double dz = -gravParams[GRAVP_Z0];
	double rXYsqr = dx*dx + dy*dy; // This is constant.
	double radius;

	__shared__ double locRho[GRAVITY_NX][GRAVITY_NY];
	__shared__ double locE  [GRAVITY_NX][GRAVITY_NY];
	__shared__ double locMom[GRAVITY_NX][GRAVITY_NY];

	double dQ;

	//int Amax = arraysize.x*arraysize.y*arraysize.z;
	int dAddr = arraysize.x * arraysize.y;
	int z;
	for(z = 0; z < arraysize.z; z++) {
		//; globAddr < Amax; globAddr += arraysize.x*arraysize.y) {
		locRho[threadIdx.x][threadIdx.y] = rho[globAddr];
		locE  [threadIdx.x][threadIdx.y] = E[globAddr];

		if(locRho[threadIdx.x][threadIdx.y] > RHOGRAV) {
			radius = sqrt(rXYsqr + dz*dz);

			dQ = gravParams[GRAVP_GMDT] / (radius*radius*radius);
			// We have dQ = -G*M*dt*rhat / r^3
			// Then change in momentum = dP = F dt = rho d[x y z] dQ
			// And change in energy    = dE = F dot V dt = rho * V * d[x y z] dQ = P * d[x y z] * dQ;
			locMom[threadIdx.x][threadIdx.y] = px[globAddr];
			locE  [threadIdx.x][threadIdx.y] = -dQ*dx*locMom[threadIdx.x][threadIdx.y];
			px[globAddr] = locMom[threadIdx.x][threadIdx.y] - dQ*locRho[threadIdx.x][threadIdx.y]*dx;

			locMom[threadIdx.x][threadIdx.y] = py[globAddr];
			locE  [threadIdx.x][threadIdx.y] -= dQ*dy*locMom[threadIdx.x][threadIdx.y];
			py[globAddr] = locMom[threadIdx.x][threadIdx.y] - dQ*locRho[threadIdx.x][threadIdx.y]*dy;

			locMom[threadIdx.x][threadIdx.y] = pz[globAddr];
			locE  [threadIdx.x][threadIdx.y] -= dQ*dz*locMom[threadIdx.x][threadIdx.y];
			pz[globAddr] = locMom[threadIdx.x][threadIdx.y] - dQ*locRho[threadIdx.x][threadIdx.y]*dz;

			E[globAddr] += locE[threadIdx.x][threadIdx.y];
		}

		dz += H;
		globAddr += dAddr;
	}

}
