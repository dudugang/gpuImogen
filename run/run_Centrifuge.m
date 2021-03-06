%function result = tsCentrifuge(iniResolution, doublings, w0)
iniResolution = [512 512 1];
doublings = 1; % will run from 32x32 to 2Kx2K
w0 = 1.5;
% The centrifuge test provides an effective test for Imogen's rotating frame
% It calculates the equilibrium defined by a rotating-on-cylinders 2d fluid
% i.e. (drho/dr) (dP/drho) = - rho r w(r)^2
% which ends with w(r > 1) = 0, rho(r > 1) = 1 and P(r > 1) = 1.
% The simulation then proceeds for an adiabatic fluid with index run.gamma
%
% This system is inextricably unstable (Rayleigh criterion locally, global
% eigenmodes exist also)

grid = iniResolution;
run                 = CentrifugeInitializer(grid);
run.iterMax         = 50000;

tDynamic = 2*pi/w0;

run.timeMax = 15*tDynamic;

run.image.interval  = 100;
%run.image.speed     = true;
run.image.mass      = true;

%run.activeSlices.xy = true;
%run.activeSlices.xz = true;
run.activeSlices.xyz = true;
run.ppSave.dim3 = 5;

run.bcMode.x        = ENUM.BCMODE_CONSTANT;
run.bcMode.y        = ENUM.BCMODE_CONSTANT;
run.bcMode.z        = ENUM.BCMODE_CIRCULAR;

run.edgeFraction    = 1; % Sets the radius of the simulation to
% (1+this) times the size of the centrifuged region
run.gamma           = 5/3; % Sets the adiabatic index for fluid evolution
% w0 = 2 assures mildly supersonic flow on part of the grid
run.omega0          = w0; % Sets the w0 of w(r) = w0 (1-cos(2 pi r)) in the default rotation curve
run.rho0            = 1; % Sets the density at r >= 1 & the BC for the centrifuge region
run.P0              = 1;
run.minMass         = 1e-5; % enforced minimum density
run.frameParameters.omega= 0; % The rate at which the frame is rotating
run.eqnOfState      = run.EOS_ADIABATIC;
% EOS_ISOTHERMAL or EOS_ADIABATIC or EOS_ISOCHORIC

run.pureHydro = true;

rp = RealtimePlotter();
  rp.plotmode = 4;
  rp.plotDifference = 1;
  rp.insertPause = 1;
  rp.spawnGUI = 1;
  rp.iterationsPerCall = 10;
  rp.firstCallIteration = 1;
run.peripherals{end+1} = rp;

run.info        = 'Testing centrifuged fluid equilibrium against rotating frame';
run.notes       = '';

run.image.parallelUniformColors = true;

result.T = [];
result.L1 = [];
result.L2 = [];
result.paths={};

for N = 1:doublings
    % Run test
    disp(['Running at resolution: ',mat2str(grid)]);
    run.geomgr.setup(grid);
    
    icfile   = run.saveInitialCondsToFile();
    outdir   = imogen(icfile);

    % Get metric error norms
    a = CentrifugeAnalysis(outdir, 1);

    % Paste them together
    result.T(end+1,:)   = a.T;
    result.L1(end+1,:)  = a.L1;
    result.L2(end+1,:)  = a.L2;
    result.paths{end+1} = outdir; 

    grid = grid*2;
    grid(3) = grid(3) / 2; % keep ini Z resolution, should be 1 anyway
end

d0 = pwd(); cd(outdir);
save('./tsCentrifugeResult2.mat','result');
cd(d0);

%end
