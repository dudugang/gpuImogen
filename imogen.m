function outdirectory = imogen(srcData, resumeinfo)
% This is the main entry point for the Imogen MHD code. It contains the primary evolution loop and 
% the hooks for writing the results to disk.
%
%> srcData         Either filename from Initializer.saveInitialCondsToFile
%                  or structure from Initializer.saveInitialCondsToStructure
%> resumeinfo      If present, structure as in run/special_Resume.m
%< outdirectory    Path to directory containing output data

    if isstruct(srcData) == 0
        load(srcData); %#ok<LOAD>
        SaveManager.logPrint('---------- Imogen starting from file');
    else
        IC = srcData;
        clear srcData;
        evalin('caller','clear IC'); % Make ML release the memory used above
        SaveManager.logPrint('---------- Imogen starting from passed IC structure');
    end

    ini     = IC.ini;
    statics = IC.statics;

    collectiveFailure = 0;

    %--- Parse initial parameters from ini input ---%
    %       The initialize function parses the ini structure input and populates all of the manager
    %       classes with the values. From these values the initializeResultsPaths function 
    %       establishes all of the save directories for the run, creating whatever directories are
    %       needed in the process.
    run = initialize(ini);

    if isfield(IC, 'amResuming'); RESTARTING = true; else; RESTARTING = false; end

    % Behavior depends if IC.originalPathStruct exists
    initializeResultPaths(run, IC)

    outdirectory = run.paths.save;
    run.save.saveIniSettings(ini);

    mpi_barrier();

    if RESTARTING
        run.save.logPrint('   Accessing restart data files\n');
        % If reloading from time-evolved point,
        % garner important values from saved files:
        % (1) save paths [above]
        % (2) Q(x,t0) from saved files
        % WARNING - this really, really needs to _know_ which frame type to load
        origpath=pwd(); cd(run.paths.save);
        dframe = util_LoadFrameSegment('2D_XY', mpi_myrank(), resumeinfo.frame);
        % (3) serialized time history, from saved data files, except for newly adultered time limits.
        run.time.resumeFromSavedTime(dframe.time, resumeinfo);
        run.image.frame = resumeinfo.imgframe;

        cd(origpath); clear origpath;
        FieldSource = dframe;
    else
        FieldSource = IC;
    end

    try
        [run.fluid, mag] = uploadDataArrays(FieldSource, run, statics);
    catch oops
        prettyprintException(oops, 0, ...
            sprintf('\n    FATAL: Unsuccessful uploading data arrays!\n    Aborting run.\n    Additional execption will be printed by loader.\n'));
        collectiveFailure = 1;
    end
    mpi_errortest(collectiveFailure);

    writeSimInitializer(run, IC);

    %--- Pre-loop actions ---%
    SaveManager.logPrint('---------- Setting up any other physics subsystems\n');
    run.initialize(IC, mag);

    srcFunc = sourceChooser(run, run.fluid, mag);

    clear('IC', 'ini', 'statics');    
    mpi_barrier();
    run.save.logPrint('---------- Entering simulation loop\n');

    if ~RESTARTING
        run.save.logPrint('New simulation: Doing initial save... ');
        try
            resultsHandler([], run, run.fluid, mag);
        catch booboo
            prettyprintException(booboo, 0, ...
                '    FATAL: First resultsHandler() call failed! Data likely unaccessible. Aborting run.\n');
            collectiveFailure = 1;
        end
        mpi_errortest(collectiveFailure); % All ranks will error() if any failed, & make loader abort

        run.save.logPrint('Succeeded.\n');
    else
        run.save.logPrint('Simulation resuming after iteration %i\n',run.time.iteration);
    end

    run.time.recordWallclock();

    if run.checkpointInterval
        run.save.logPrint(['Checkpointing enabled, interval ' num2str(run.checkpointInterval) ' steps.']);
        backupData = dumpCheckpoint(run);
    end

run.time.updateUI();

    %%%=== MAIN ITERATION LOOP ==================================================================%%%
    while run.time.running
        run.time.update(run.fluid, mag); % chooses dt
        if run.chkpointThisIter()
            backupData = dumpCheckpoint(run);
        end
        
        srcFunc(run, run.fluid, mag, 0.5);
        fluidstep(run.fluid, mag(1).cellMag, mag(2).cellMag, mag(3).cellMag, [run.time.dTime 1  1 run.time.iteration run.cfdMethod], run.geometry);
        srcFunc(run, run.fluid, mag, 1.0);
        fluidstep(run.fluid, mag(1).cellMag, mag(2).cellMag, mag(3).cellMag, [run.time.dTime 1 -1 run.time.iteration run.cfdMethod], run.geometry);
        srcFunc(run, run.fluid, mag, 0.5);
        
        if run.VTOSettings(1)
            % This isn't a physical operator anyway so don't cry about temporal accuracy
            cudaSourceVTO(run.fluid(1), [run.time.dTime, run.VTOSettings(2:3)], run.geoetry);
        end
        
        if run.checkpointInterval && checkPhysicality(run.fluid)
            restoreCheckpoint(run, backupData);
        end
        
        run.time.step(); % updates t -> t+2dt
        run.pollEventList(run.fluid, mag);
    end
    %%%=== END MAIN LOOP ========================================================================%%%

% FIXME: This is a terrible hack.
if mpi_amirank0() && numel(run.selfGravity.compactObjects) > 0
  starpath = sprintf('%s/starpath.mat',run.paths.save);
  stardata = run.selfGravity.compactObjects{1}.history; %#ok<NASGU>
  save(starpath,'stardata');
end

    run.finalize(run.fluid, mag);

end
