
% Run sonic advection test at 3 different resolutions,
% Check accuracy & scaling

TestResults.name = 'Imogen Master Test Suite';

%--- Override: Run ALL the tests! ---%
doALLTheTests = 0;
realtimePictures = 1;

%--- Individual selects ---%
% Advection/transport tests
doSonicAdvectStaticBG = 0;
doSonicAdvectMovingBG = 0;
doSonicAdvectAngleXY  = 0;
doEntropyAdvect       = 0;

% 1D tests
doSodTubeTests        = 0;
doEinfeldtTests       = 0;

% 2D tests
doCentrifugeTests     = 0;

% 3D tests
doSedovTests          = 1;

% As regards the choices of arbitrary inputs like Machs...
% If it works for $RANDOM_NUMBER_WITH_NO_PARTICULAR_SIGNIFICANCE
% It's probably right

baseResolution = 32;

if mpi_amirank0();
    fprintf('NOTICE: Base resolution is currently set to %i.\nNOTICE: If the number of MPI ranks or GPUs will divide this to below 6, things will Break.\n', baseResolution);
end

% Picks how far we take the scaling tests
advectionDoublings  = 6;
einfeldtDoublings   = 7;
sodDoublings        = 7;
centrifugeDoublings = 6;
sedov2D_scales      = [1 2 4 8 16 32];
sedov3D_scales      = [1 2 3 4 8];

%--- Gentle one-dimensional test: Advect a sound wave in X direction ---%
if doSonicAdvectStaticBG || doALLTheTests
    if mpi_amirank0(); disp('Testing advection against stationary background.'); end
    try
        x = tsAdvection('sonic',[baseResolution 2 1], [1 0 0], [0 0 0], 0, advectionDoublings, realtimePictures);
    catch ME
        fprintf('Oh dear: 1D Advection test simulation barfed.\nIf this wasn''t a mere syntax error, something is seriously wrong\nRecommend re-run full unit tests. Storing blank.\n');
        prettyprintException(ME);
        x = 'FAILED';
    end
    TestResult.advection.Xalign_mach0 = x;
    if mpi_amirank0(); disp('Results for advection against stationary background:'); disp(x); end
end

%--- Test advection of a sound wave with the background translating at half the speed of sound ---%
if doSonicAdvectMovingBG || doALLTheTests
    if mpi_amirank0(); disp('Testing advection against moving background'); end
    try
        x = tsAdvection('sonic',[baseResolution 2 1], [1 0 0], [0 0 0], -.526172, advectionDoublings, realtimePictures);
    catch ME
        fprintf('Oh dear: 1D Advection test simulation barfed.\nIf this wasn''t a mere syntax error, something is seriously wrong\nRecommend re-run full unit tests. Storing blank.\n');
        prettyprintException(ME);
        x = 'FAILED';
    end
        
    TestResult.advection.Xalign_mach0p5 = x;
    if mpi_amirank0(); disp('Results for advection against moving background:'); disp(x); end
end

%--- Test a sound wave propagating in a non grid aligned direction at supersonic speed---%
if doSonicAdvectAngleXY || doALLTheTests
    if mpi_amirank0(); disp('Testing advection in 2D across moving background'); end
    try
        x = tsAdvection('sonic',[baseResolution baseResolution 1], [5 3 0], [0 0 0], .4387, advectionDoublings, realtimePictures);
    catch ME
        fprintf('2D Advection test simulation barfed.\n');
        prettyprintException(ME);
        x = 'FAILED';
    end

    TestResult.advection.XY = x;
    if mpi_amirank0(); disp('Results for cross-grid sonic advection with moving background:'); disp(x); end
end

% This one is unhappy. It expects to have a variable defined (the self-rest-frame oscillation frequency) that isn't set for this type
%--- Test that an entropy wave just passively coasts along as it ought ---% 
%if doEntropyAdvect || doALLTheTests
%    TestResult.advection.HDentropy = tsAdvection('entropy',[1024 1024 1], [9 5 0], [0 0 0], 2.1948, doublings);
%end

%--- Run an Einfeldt double rarefaction test at the critical parameter ---%
if doEinfeldtTests || doALLTheTests
    if mpi_amirank0(); disp('Testing convergence of Einfeldt tube'); end
    try
        x = tsEinfeldt(baseResolution, 1.4, 1.9, einfeldtDoublings, realtimePictures);
    catch ME
        fprintf('Einfeldt tube test has failed.\n');
        prettyprintException(ME);
        x = 'FAILED';
    end
    TestResult.einfeldt = x;
    if mpi_amirank0(); disp('Results for Einfeldt tube refinement:'); disp(x); end
end

%--- Test the Sod shock tube for basic shock-capturingness ---%
if doSodTubeTests || doALLTheTests
    if mpi_amirank0(); disp('Testing convergence of Sod tube'); end
    try
        x = tsSod(baseResolution, 1, sodDoublings, realtimePictures);
    catch ME
        fprintf('Sod shock tube test has failed.\n');
        prettyprintException(ME);
        x = 'FAILED';
    end
    
    TestResult.sod.X = x;
    if mpi_amirank0(); disp('Results for Sod tube refinement:'); disp(x); end
end

if doCentrifugeTests || doALLTheTests
    if mpi_amirank0(); disp('Testing centrifuge equilibrium-maintainence.'); end
    try
        x = tsCentrifuge([baseResolution baseResolution 1], 1.5, centrifugeDoublings, realtimePictures); 
    catch ME
        disp('Centrifuge test has failed.');
        prettyprintException(ME);
        x = 'FAILED';
    end

    TestResult.centrifuge = x;
    if mpi_amirank0(); disp('Results for centrifuge test in stationary frame:'); disp(x); end
    % FIXME: Run a centrifuge with a rotating frame term!
end


%--- Test propagation across a three-dimensional grid ---%
% Not sure that this mode actually works in the analyzer, though it will certainly work in the initializer
%if doSonicAdvectXYZ
%    TestResult.advection.XYZ = test
%end
%--- Run same battery of tests with entropy wave, magnetized entropy wave, MHD waves ---%

% Run OTV at moderate resolution, compare difference blah blah blah

%%% 3D tests
if doSedovTests || doALLTheTests
    if mpi_amirank0(); disp('Testing 2D Sedov-Taylor explosion'); end
    try
        x = tsSedov([baseResolution baseResolution 1], sedov2D_scales, realtimePictures);
    catch ME
        disp('2D Sedov-Taylor test has failed.');
        prettyprintException(ME);
        x = 'FAILED';
    end
    TestResult.sedov2d = x;
    if mpi_amirank0(); disp('Results for 2D (cylindrical) Sedov-Taylor explosion:'); disp(x); end

    if mpi_amirank0(); disp('Testing 3D Sedov-Taylor explosion'); end
    try
        x = tsSedov([baseResolution baseResolution baseResolution], sedov3D_scales, realtimePictures);
    catch ME
        disp('3D Sedov-Taylor test has failed.');
        prettyprintException(ME);
        x = 'FAILED';
    end

    TestResult.sedov3d = x;
    if mpi_amirank0(); disp('Results for 3D (spherical) Sedov-Taylor explosion:'); disp(x); end
end

%%%%%
% Test standing shocks, HD and MHD, 1/2/3 dimensional



%%% SOURCE TESTS???
% Test constant gravity field, (watch compressible water slosh?)

% Test RT magnetically-stabilized transverse oscillation?
% REQUIRES MAGNETISM

% Test behavior of radiative flow
% REQUIRES MAGNETISM

% Test rotating frame
% USE CENTRIFUGE TEST

if mpi_amirank0()
    save('~/FullTestSuiteResults_SERIAL_1GPU.mat','TestResult');
end


