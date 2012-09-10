function parImogenLoad(runFile, logFile, alias, gpuno)
% This script is the command and control manager for command line run Imogen scripts. It is
% designed to simplify the run script syntax and allow for greater extensibility.
% 
%>> runFile		run file function name to execute								str
%>> logFile		log file name for writing output information					str
%>> uid         unique identifier string for the run                            str

    %-- Initialize Imogen directory ---%
    starterRun();

    %--- Initialize MPI and GPU ---%
    mpi_init();

    mpiInfo = mpi_basicinfo();
    if mpiInfo(1) > 1 % If this is in fact parallel, autoinitialize GPUs
                     % Otherwise initialize.m will choose one manually
        fprintf('MPI size > 1; We are running in parallel: Autoselecting GPUs\n');

        y = mpi_allgather(mpiInfo(2:3));
        ranks = y(1:2:end);
        hash = y(2:2:end);

        % Select ranks on this node, sort them, chose my gpu # by resultant ordering
        thisnode = ranks(hash == mpiInfo(3));
        [dump idx] = sort(thisnode);
        mygpu = idx(dump == mpiInfo(2)) - 1;
        fprintf('Rank %i/%i (on host %s) activating GPU number %i\n', mpiInfo(2), mpiInfo(1), getenv('HOSTNAME'), mygpu);
        GPU_init(mygpu);

%        context = parallel_start();

%        [
    else
        GPU_init(gpuno);
    end

    runFile = strrep(runFile,'.m','');
    assignin('base','logFile',logFile);
    assignin('base','alias',alias);
    try
        eval(runFile);
    catch ME
       rethrow(ME);
    end

    mpi_barrier();
    mpi_finalize();

    exit;
end
