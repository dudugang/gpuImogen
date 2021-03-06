# Compiles (real) MPI support needed in Matlab that PGW doesn't yet include.

include ../Make.config

# Don't mess with these
NVCC_OPTS = -arch=$(CUDA_ARCH) -O1 -g
NVCC_INCL = -I$(MATLAB_DIR)/extern/include

MEX_OPTS = -DUNIX -g -R2018a -DDEBUG_OUTPUT
MEX_INCL = -I$(MATLAB_DIR)/extern/include
MEX_LIBS = 
MEX_LDIR = -L$(MATLAB_DIR)/runtime/glnxa64

PAR_INCL = -I$(MPI_DIR)/include
PAR_LDIR = -L$(MPI_DIR)/lib
PAR_LIBS = -lmpi -lmpi_cxx

###############################################################################
all: mpi_informative mpi_therest teststuff

teststuff: mpi_send mpi_recv

mpi_send mpi_recv:
	 mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) $@.cpp -output $@



mpi_therest: debugSpin mpi_abort mpi_all mpi_allgather mpi_any mpi_barrier mpi_dimreduce mpi_min mpi_max mpi_sum mpi_prod mpi_scatter mpi_createDimcomm mpi_deleteDimcomm generateTestExchanges
	echo "Built remaining mpi functions"

mpi_informative: mpi_amirank0 mpi_basicinfo mpi_errortest mpi_init mpi_isinitialized mpi_finalize mpi_myrank
	echo "Done building informative functions"

standalone: mpi_standalone_helloworld.c
	gcc -I$(CUDA_DIR)/include -L$(CUDA_DIR)/lib64 mpi_standalone_helloworld.c -o mpi_hello -lmpi -lcudart

wrapper:
	g++ -I$(CUDA_DIR)/include $(PAR_INCL) -fPIC  -c nvtx_wrapper.cpp

generateTestExchanges: generateTestExchanges.cpp mpi_common.o
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) -output generateTestExchanges mpi_common.o generateTestExchanges.cpp

debugSpin: debugSpin.cpp
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) -output debugSpin debugSpin.cpp

mpi_common.o: mpi_common.cpp
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(PAR_INCL) -c mpi_common.cpp

mpi_min: mpi_allreduce.cpp mpi_common.o
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) -DMPIOPERATION=MPI_MIN mpi_allreduce.cpp mpi_common.o -output mpi_min

mpi_max: mpi_allreduce.cpp mpi_common.o
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) -DMPIOPERATION=MPI_MAX mpi_allreduce.cpp mpi_common.o -output mpi_max

mpi_sum: mpi_allreduce.cpp mpi_common.o
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) -DMPIOPERATION=MPI_SUM mpi_allreduce.cpp mpi_common.o -output mpi_sum

mpi_prod: mpi_allreduce.cpp mpi_common.o
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) -DMPIOPERATION=MPI_PROD mpi_allreduce.cpp mpi_common.o -output mpi_prod

mpi_all mpi_any mpi_amirank0 mpi_allgather mpi_barrier mpi_basicinfo mpi_dimreduce mpi_finalize mpi_init mpi_isinitialized mpi_myrank mpi_reduce mpi_scatter mpi_errortest mpi_abort mpi_createDimcomm mpi_deleteDimcomm: mpi_common.o
	mex $(MEX_OPTS) $(MEX_INCL) $(MEX_LDIR) $(MEX_LIBS) $(PAR_INCL) $(PAR_LDIR) $(PAR_LIBS) $@.cpp mpi_common.o -output $@

clean:
	rm -f *mexa64 mpi_common.o

