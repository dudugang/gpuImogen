%function imogen(massDen, momDen, enerDen, magnet, ini, statics)
function imogen(icfile)
% This is the main entry point for the Imogen MHD code. It contains the primary evolution loop and 
% the hooks for writing the results to disk.
%
%>> massDen     Mass density array (cell-centered).                         double  [nx ny nz]
%>> momDen      Momentum density array (cell-centered).                     double  [3 nx ny nz]
%>> enerDen     Energy density array (cell-centered).                       double  [nx ny nz]
%>> magnet      Magnetic field strength array (face-centered).              double  [3 nx ny nz]
%>> ini         Listing of properties and settings for the run.             struct
%>> statics     Static arrays with lookup to static values.                 struct

    load(icfile);
    massDen = IC.mass;
    momDen  = IC.mom;
    enerDen = IC.ener;
    magnet  = IC.magnet;
    ini     = IC.ini;
    statics = IC.statics;
    clear IC;
%   delete icfile;
    system(['rm -f ' icfile ]);

    %--- Parse initial parameters from ini input ---%
    %       The initialize function parses the ini structure input and populates all of the manager
    %       classes with the values. From these values the initializeResultsPaths function 
    %       establishes all of the save directories for the run, creating whatever directories are
    %       needed in the process. 
    run = initialize(ini);
    initializeResultPaths(run);
    run.save.saveIniSettings(ini);
    run.preliminary();

    mass = FluidArray(ENUM.SCALAR, ENUM.MASS, massDen, run); mass.readStatics(statics); mass.applyStatics;
    ener = FluidArray(ENUM.SCALAR, ENUM.ENER, enerDen, run); ener.readStatics(statics); ener.applyStatics;
    grav = GravityArray(ENUM.GRAV, run);
    mom  = FluidArray.empty(3,0);
    mag  = MagnetArray.empty(3,0);
    for i=1:3
        mom(i) = FluidArray(ENUM.VECTOR(i), ENUM.MOM, momDen(i,:,:,:), run); mom(i).readStatics(statics); mom(i).applyStatics;
        mag(i) = MagnetArray(ENUM.VECTOR(i), ENUM.MAG, magnet(i,:,:,:), run); mag(i).readStatics(statics); mag(i).applyStatics;
    end

    %--- Pre-loop actions ---%
    run.fluid.createFreezeArray();
    clear('massDen','momDen','enerDen','magnet','ini','statics');    
    run.initialize(mass, mom, ener, mag, grav);
    
    resultsHandler(run, mass, mom, ener, mag, grav);
    run.time.iteration  = 1;
    direction           = [1 -1];

    run.save.logPrint('\nBeginning simulation loop...\n');

    clockA = clock;
 
    %%%=== MAIN ITERATION LOOP ==================================================================%%%
    while run.time.running
        %run.time.updateUI();
        
        for i=1:2 % Two timesteps per iteration
            run.time.update(mass, mom, ener, mag, i);
            fluxB(run, mass, mom, ener, mag, grav, direction(i));
% change this to 'fluxB' for devel work
            treadmillGrid(run, mass, mom, ener, mag);
            run.gravity.solvePotential(run, mass, grav);
            source(run, mass, mom, ener, mag, grav);
        end
%input('cont: ');
% Dumb hack to push realtime images to a display
%        if mod(run.time.iteration, 10) == 1
%            imagesc(double(mass.array))
%            pause(.5);
%        end

        %--- Intermediate file saves ---%
        resultsHandler(run, mass, mom, ener, mag, grav);
        run.time.step();
    end
    %%%=== END MAIN LOOP ========================================================================%%%
    fprintf('%g seconds in main sim loop\n', etime(clock, clockA));
    %error('devel prevent-matlab-exiting stop')

    run.postliminary();
end
