function result = tsAdvection(wavetype, grid, N0, B0, V0, doublings, prettyPictures, methodPicker)

if nargin < 6
    if mpi_amirank0(); disp('Number of grid resolution doublings not given: defaulted to 3'); end 
    doublings = 3;
end
if nargin < 7
    prettyPictures = 0;
end

run         = AdvectionInitializer(grid);
run.iterMax = 499999;
run.info    = 'Advection test.';
run.notes   = 'Automated test suite: Advection';

%run.image.interval = 100;
%run.image.mass = true;

run.activeSlices.x = false;
run.activeSlices.xy = false;
run.activeSlices.xyz = true;

run.ppSave.dim1 = 100;
run.ppSave.dim2 = 100;

% Set a background speed at which the fluid is advected to 0
run.backgroundMach = V0;

% Set the type of wave to be run.
% One of 'entropy', 'sound', 'alfven', 'sloww ma', 'fast ma'
% The MHD waves require a B to be set; Setting one is optional for the Entropy wave.
% Any nonzero B will automatically activate magnetic fluxing, and turn 'sonic' into 'fast ma'
% as the fast branch merges with the sonic branch of the dispersion relation
run.waveType = wavetype;
run.amplitude = .01;
run.waveLinearity(0);
run.waveStationarity(0);
% FWIW an amplitude of .01 corresponds to a roughly 154dB sound in air

run.backgroundB = B0;
run.ppSave.dim3 =  100;

run.wavenumber = N0;
% run for only 1/3 because this will decrease by factor of 3 at 3x the wavenumber

% Worth warning, this will diverge as 1/amplitude when amplitude is small...
run.forCriticalTimes(.95);
%run.cycles = 4;
run.alias = sprintf('ADVECTtestsuite_N%i_%i_%i',run.wavenumber(1),run.wavenumber(2),run.wavenumber(3));

if prettyPictures
    rp = RealtimePlotter();
    rp.plotmode = 1;
    if grid(2) > 3; rp.plotmode = 4; end
    rp.plotDifference = 0;
    rp.insertPause = 0;
    rp.firstCallIteration = 1;
    rp.iterationsPerCall = 10;
    rp.spawnGUI = 1;
    run.peripherals{end+1} = rp;
end
if nargin == 8
    run.peripherals{end+1} = methodPicker;
end

result.firstGrid = grid;
result.doublings = doublings;
result.paths = cell([doublings 1]);
result.L1 = zeros([1 doublings]); result.L2 = zeros([1 doublings]);
result.N = zeros([1 doublings]);

for D = 1:doublings;
    % Run simulation at present resolution & store results path
    IC = run.saveInitialCondsToStructure();
    outpath = imogen(IC);

    enforceConsistentView(outpath); 
    A = SonicAdvectionAnalysis(outpath, 1);
    result.paths{end+1} = outpath;

    % Store error norms
    result.L1(D) = A.rhoL1(end);
    result.L2(D) = A.rhoL2(end);
    result.N(D) = grid(1);

    % Refine grid
    grid=grid*2;
    if grid(2) <= 2; grid(2) = 1; end % keep 1D from becoming 2D
    if grid(3) <= 2; grid(3) = 1; end % keep 1D/2D from becoming 3D
    run.geomgr.setup(grid);
end

if numel(B0) < 3; B0 = [1 1 1]*B0(1); end % Prevent descriptor sprintf from barfing
if numel(V0) < 3; V0 = [1 0 0]*V0(1); end

L1_Order = mean(diff(log(result.L1)) ./ diff(log(result.N)));
L2_Order = mean(diff(log(result.L2)) ./ diff(log(result.N)));

result.L1_Order = L1_Order;
result.L2_Order = L2_Order;

result.about = sprintf('Tested advection of wave of type %s\nWavevector=<%g %g %g>\nIni grid=<%g %g %g>\nB0=<%g %g %g>\nV0=c_s*<%g %g %g>', wavetype, N0(1), N0(2), N0(3), result.firstGrid(1), result.firstGrid(2), result.firstGrid(3), B0(1), B0(2), B0(3), V0(1), V0(2), V0(3));
result.result = sprintf('Average dlog(L1)/dlog(h) = %f; Average dlog(L2)/dlog(h) = %f\n', result.L1_Order, result.L2_Order);

end
