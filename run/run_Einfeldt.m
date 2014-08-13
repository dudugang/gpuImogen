% Run Einfeldt Strong Rarefaction test.

%-- Initialize Imogen directory ---%
starterRun();

grid = [1024 8 1];
GIS = GlobalIndexSemantics(); GIS.setup(grid);

%--- Initialize test ---%
run             = EinfeldtInitializer(grid);
run.direction   = EinfeldtInitializer.X;
run.shockAngle  = 0;
run.timeMax     = 0.1;
run.iterMax     = 2*run.timeMax*grid(1); % This will give steps max ~ 1.2x required

run.rhol	= 1;
run.ml		= -1;
run.nl		= 0;
run.el		= 5;

run.rhor	= 1;
run.mr		= 1;
run.nr		= 0;
run.er		= 5;
% Note that with HLL, a Delta m of greater than 2.1 results in too great of a rarefaction, resulting in negative mass density and NAN-Plague.
run.alias       = '';
run.info        = 'Einfeldt Strong Rarefaction test.';
%run.notes       = 'Simple axis aligned  test';

run.ppSave.dim2 = 5;

%--- Run tests ---%
if (true)
    icfile = run.saveInitialCondsToFile();
    imogen(icfile);
end

