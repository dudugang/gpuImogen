% Wave advection simulation

grid = [128 1 1];
%grid = [32 1 1];

%--- Initialize test ---%
run             = AdvectionInitializer(grid);
run.iterMax     = 20000;
run.info        = '2-fluid advection test';
run.notes       = 'basic testbed for 2-fluid drag code';

%run.image.interval = 100;
%run.image.mass = true;

run.activeSlices.x = false;
run.activeSlices.xy = false;
run.activeSlices.xyz = false;

run.ppSave.dim1 = 100;
run.ppSave.dim2 = 10;

% Set a background speed at which the fluid is advected
run.backgroundMach = -0;

% Set the type of wave to be run.
% One of 'entropy', 'sound', 'alfven', 'slow ma', 'fast ma'
% The MHD waves require a B to be set; Setting one is optional for the Entropy wave.
% Any nonzero B will automatically activate magnetic fluxing
run.waveType = 'sonic';
run.amplitude = .001;

% FWIW an amplitude of .0001 corresponds to a roughly 100dB sound in air
%                      .01                    roughly 140dB

% number of transverse wave periods in Y and Z directions
run.wavenumber = [1 0 0];
% 1st method of setting run duration: normalized by cycle time
run.cycles = 25;

run.setBackground(.084, 101325);

run.addNewFluid(1);

run.fluidDetails(1) = fluidDetailModel('cold_molecular_hydrogen');
run.fluidDetails(2) = fluidDetailModel('10um_iron_balls');
run.fluidDetails(2).sigma = run.fluidDetails(2).sigma * 1e1;
run.fluidDetails(2).mass = run.fluidDetails(2).mass * 1e-4; %

run.writeFluid = 2;
  run.amplitude = 0;
  run.backgroundMach = 0;
  run.setBackground(1, .0001*101325);

run.alias= 'dustybox';

run.ppSave.dim3 = 100;

%run.multifluidDragMethod = ENUM.MULTIFLUID_RK4;

fm = FlipMethod();
  fm.iniMethod = ENUM.CFD_HLLC; 
%  fm.toMethod = ENUM.CFD_HLLC;
%  fm.atstep = -1;
run.peripherals{end+1} = fm;

rp = RealtimePlotter();
  rp.plotmode = 5;
  rp.plotDifference = 0;
  rp.insertPause = 1;
  rp.forceRedraw = 1;
  rp.iterationsPerCall = 1;
  rp.firstCallIteration = 1;
  rp.firstCallTime = 1;
  rp.spawnGUI = 1;
  
  rp.plotmode = 4;
rp.cut = [round(grid(1)/2), 1, 1];
rp.indSubs = [1 1 grid(1);1 1 1;1 1 1];

rp.movieProps(0, 0, 'RTP_');

    rp.vectorToPlotprops(1, [1   1   0   1   1   1   0   1   0   1  10   1   8   1   0   0   0]);
rp.vectorToPlotprops(2, [1   5   0   1   1   1   0   1   0   1  10   1   8   1   0   0   0]);
rp.vectorToPlotprops(3, [2   1   0   1   1   1   0   1   0   1  10   1   8   1   0   0   0]);
rp.vectorToPlotprops(4, [2   5   0   1   1   1   0   1   0   1  10   1   8   1   0   0   0]);

run.peripherals{end+1} = rp;


run.waveLinearity(0);
run.waveStationarity(0);

%--- Run tests ---%
if true
    IC = run.saveInitialCondsToStructure();
    outpath = imogen(IC);
    if mpi_amirank0(); fprintf('RUN STORED AT: %s\n', outpath); end
end
